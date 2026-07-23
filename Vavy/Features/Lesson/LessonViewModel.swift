import Combine
import Foundation

@MainActor
final class LessonViewModel: ObservableObject {
    @Published private(set) var lesson: Lesson?
    @Published private(set) var currentIndex = 0
    @Published private(set) var isLoadingLesson = false
    @Published private(set) var isEvaluating = false
    @Published var errorMessage: String?
    @Published var latestAssessment: AssessmentResult?
    @Published private(set) var latestAudioQualityReport: AudioQualityReport?
    @Published private(set) var latestToneAnalysis: ToneAnalysisResult?
    @Published var backendBaseURLString: String

    let audioRecorder: AudioRecorder
    let itemHistoryStore: ItemHistoryStore
    #if DEBUG
    let debugAttemptStore: AttemptDebugStore
    #endif

    private var apiClient: APIClient
    private let audioQualityAnalyzer: AudioQualityAnalyzer
    private let toneContourAnalyzer: ToneContourAnalyzer
    private var cancellables = Set<AnyCancellable>()
    private var isFinishingRecording = false

    convenience init() {
        self.init(
            apiClient: APIClient(),
            audioRecorder: AudioRecorder(),
            audioQualityAnalyzer: AudioQualityAnalyzer(),
            lesson: nil
        )
    }

    init(
        apiClient: APIClient,
        audioRecorder: AudioRecorder,
        audioQualityAnalyzer: AudioQualityAnalyzer,
        toneContourAnalyzer: ToneContourAnalyzer = ToneContourAnalyzer(),
        itemHistoryStore: ItemHistoryStore? = nil,
        lesson: Lesson? = nil
    ) {
        self.apiClient = apiClient
        self.audioRecorder = audioRecorder
        self.audioQualityAnalyzer = audioQualityAnalyzer
        self.toneContourAnalyzer = toneContourAnalyzer
        self.itemHistoryStore = itemHistoryStore ?? ItemHistoryStore()
        self.lesson = lesson
        self.backendBaseURLString = apiClient.baseURL.absoluteString
        #if DEBUG
        self.debugAttemptStore = AttemptDebugStore()
        #endif

        audioRecorder.maximumDurationReachedHandler = { [weak self] in
            self?.stopRecordingAndEvaluate()
        }

        audioRecorder.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        audioRecorder.livePitchTracker.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        self.itemHistoryStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    /// Progress summary for the current item, driving the pass/fail badge on
    /// the prompt card.
    var currentItemHistorySummary: ItemHistorySummary {
        guard let currentItem else { return .empty }
        return itemHistoryStore.summary(for: currentItem.id)
    }

    func applyBackendBaseURL() {
        guard let url = AppConfig.normalizedBackendBaseURL(from: backendBaseURLString) else {
            errorMessage = "Enter a valid backend URL, for example http://localhost:3000 or your ngrok host."
            return
        }

        AppConfig.backendBaseURL = url
        backendBaseURLString = url.absoluteString
        apiClient = APIClient(baseURL: url)
        lesson = nil
        latestAssessment = nil
        latestAudioQualityReport = nil
        latestToneAnalysis = nil
        errorMessage = nil
        currentIndex = 0
        loadLesson()
    }

    var currentItem: TrainingItem? {
        guard let lesson, lesson.items.indices.contains(currentIndex) else { return nil }
        return lesson.items[currentIndex]
    }

    var isRecording: Bool {
        audioRecorder.isRecording
    }

    var elapsedTime: TimeInterval {
        audioRecorder.elapsedTime
    }

    var itemCount: Int {
        lesson?.items.count ?? 0
    }

    func loadLesson() {
        Task {
            await loadLessonFromBackend()
        }
    }

    func loadSampleLesson() {
        lesson = StarterLessonData.sampleLesson
        currentIndex = 0
        latestAssessment = nil
        latestAudioQualityReport = nil
        latestToneAnalysis = nil
        errorMessage = "Using the local starter lesson. Start the backend and tap Retry to load server lessons."
    }

    func prepareRecording() {
        Task {
            try? await audioRecorder.prepareSession()
        }
    }

    func endRecordingSession() {
        audioRecorder.endSession()
    }

    func startRecording() {
        guard !isEvaluating, !isFinishingRecording else { return }
        latestAssessment = nil
        latestAudioQualityReport = nil
        latestToneAnalysis = nil
        errorMessage = nil

        Task {
            do {
                try await audioRecorder.startRecording()
            } catch {
                errorMessage = userMessage(for: error)
            }
        }
    }

    func stopRecordingAndEvaluate() {
        guard let currentItem, isRecording, !isFinishingRecording else { return }
        isFinishingRecording = true
        let attemptStartedAt = Date()

        Task {
            defer { isFinishingRecording = false }
            var audioURL: URL?
            var audioQualityReport: AudioQualityReport?
            var toneAnalysisResult: ToneAnalysisResult?
            var requestStartedAt: Date?
            var requestDurationMs: Int?

            do {
                let recordedURL = try await audioRecorder.stopRecording()
                audioURL = recordedURL
                let qualityReport = try audioQualityAnalyzer.analyze(fileURL: recordedURL)
                audioQualityReport = qualityReport
                latestAudioQualityReport = qualityReport

                let toneWavFile = currentItem.category == .toneMinimalPair ? try? PCM16WAVFile(contentsOf: recordedURL) : nil
                let toneAnalysis = toneWavFile.map { toneContourAnalyzer.analyze(samples: $0.samples) }
                toneAnalysisResult = toneAnalysis
                latestToneAnalysis = toneAnalysis

                guard qualityReport.isUsable else {
                    let result = StarterLessonData.localRetryAudioAssessment(
                        expectedText: currentItem.displayText,
                        report: qualityReport
                    )
                    latestAssessment = result
                    errorMessage = nil
                    #if DEBUG
                    recordDebugAttempt(
                        source: .localAudioQuality,
                        item: currentItem,
                        audioFileURL: recordedURL,
                        audioQualityReport: qualityReport,
                        toneAnalysis: toneAnalysis,
                        requestDurationMs: nil,
                        httpStatusCode: nil,
                        assessment: result,
                        rawResponseBody: nil,
                        errorMessage: nil,
                        createdAt: attemptStartedAt
                    )
                    #endif
                    #if !DEBUG
                    try? FileManager.default.removeItem(at: recordedURL)
                    #endif
                    return
                }

                isEvaluating = true
                defer { isEvaluating = false }

                requestStartedAt = Date()
                #if DEBUG
                let response = try await apiClient.evaluateAttemptDetailed(
                    itemID: currentItem.id,
                    audioFileURL: recordedURL,
                    audioQualityReport: qualityReport,
                    toneAnalysis: toneAnalysis
                )
                requestDurationMs = elapsedMilliseconds(since: requestStartedAt)
                latestAssessment = response.result
                recordItemHistoryIfGraded(response.result, itemID: currentItem.id, createdAt: attemptStartedAt)
                recordDebugAttempt(
                    source: .backendResponse,
                    item: currentItem,
                    audioFileURL: recordedURL,
                    audioQualityReport: qualityReport,
                    toneAnalysis: toneAnalysis,
                    requestDurationMs: requestDurationMs,
                    httpStatusCode: response.statusCode,
                    assessment: response.result,
                    rawResponseBody: response.rawResponseBody,
                    errorMessage: nil,
                    createdAt: attemptStartedAt
                )
                #else
                let result = try await apiClient.evaluateAttempt(
                    itemID: currentItem.id,
                    audioFileURL: recordedURL,
                    audioQualityReport: qualityReport,
                    toneAnalysis: toneAnalysis
                )
                latestAssessment = result
                recordItemHistoryIfGraded(result, itemID: currentItem.id, createdAt: attemptStartedAt)
                #endif
                errorMessage = nil

                #if !DEBUG
                try? FileManager.default.removeItem(at: recordedURL)
                #endif
            } catch {
                let message = userMessage(for: error)
                errorMessage = message
                if requestDurationMs == nil, requestStartedAt != nil {
                    requestDurationMs = elapsedMilliseconds(since: requestStartedAt)
                }
                #if DEBUG
                recordDebugAttempt(
                    source: requestStartedAt == nil ? .clientError : .requestError,
                    item: currentItem,
                    audioFileURL: audioURL,
                    audioQualityReport: audioQualityReport,
                    toneAnalysis: toneAnalysisResult,
                    requestDurationMs: requestDurationMs,
                    httpStatusCode: nil,
                    assessment: nil,
                    rawResponseBody: nil,
                    errorMessage: message,
                    createdAt: attemptStartedAt
                )
                #endif
            }
        }
    }

    func cancelRecording() {
        audioRecorder.cancelRecording()
        latestAudioQualityReport = nil
        latestToneAnalysis = nil
    }

    func tryAgain() {
        latestAssessment = nil
        latestAudioQualityReport = nil
        latestToneAnalysis = nil
        errorMessage = nil
    }

    func nextItem() {
        guard itemCount > 0 else { return }
        currentIndex = min(currentIndex + 1, itemCount - 1)
        latestAssessment = nil
        latestAudioQualityReport = nil
        latestToneAnalysis = nil
        errorMessage = nil
    }

    func previousItem() {
        currentIndex = max(currentIndex - 1, 0)
        latestAssessment = nil
        latestAudioQualityReport = nil
        latestToneAnalysis = nil
        errorMessage = nil
    }

    func goToItem(_ index: Int) {
        guard itemCount > 0, (0..<itemCount).contains(index) else { return }
        currentIndex = index
        latestAssessment = nil
        latestAudioQualityReport = nil
        latestToneAnalysis = nil
        errorMessage = nil
    }

    func backToLesson() {
        latestAssessment = nil
    }

    private func loadLessonFromBackend() async {
        isLoadingLesson = true
        defer { isLoadingLesson = false }

        do {
            let lesson = try await apiClient.fetchStarterLesson()
            self.lesson = lesson
            currentIndex = 0
            latestAssessment = nil
            latestAudioQualityReport = nil
            latestToneAnalysis = nil
            errorMessage = nil
        } catch {
            if lesson == nil {
                lesson = StarterLessonData.sampleLesson
                currentIndex = 0
            }
            latestAudioQualityReport = nil
            latestToneAnalysis = nil
            errorMessage = "Could not load the backend lesson. \(userMessage(for: error)) Showing the local starter lesson for now."
        }
    }

    private func userMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let message = localizedError.errorDescription {
            return message
        }
        return "Something went wrong. Try again."
    }

    private func elapsedMilliseconds(since startDate: Date?) -> Int? {
        guard let startDate else { return nil }
        return Int((Date().timeIntervalSince(startDate) * 1_000).rounded())
    }

    /// Only `.passed`/`.notPassed` are a real pronunciation verdict worth
    /// counting toward progress — `.retryAudioQuality`/`.backendError` mean
    /// the attempt was never actually judged.
    private func recordItemHistoryIfGraded(_ result: AssessmentResult, itemID: String, createdAt: Date) {
        guard result.status == .passed || result.status == .notPassed else { return }
        itemHistoryStore.record(itemID: itemID, status: result.status, strictScore: result.strictScore, createdAt: createdAt)
    }

    #if DEBUG
    private func recordDebugAttempt(
        source: AttemptDebugSource,
        item: TrainingItem,
        audioFileURL: URL?,
        audioQualityReport: AudioQualityReport?,
        toneAnalysis: ToneAnalysisResult? = nil,
        requestDurationMs: Int?,
        httpStatusCode: Int?,
        assessment: AssessmentResult?,
        rawResponseBody: String?,
        errorMessage: String?,
        createdAt: Date
    ) {
        debugAttemptStore.record(
            source: source,
            item: item,
            backendBaseURL: apiClient.baseURL,
            audioFileURL: audioFileURL,
            audioQualityReport: audioQualityReport,
            toneAnalysis: toneAnalysis,
            requestDurationMs: requestDurationMs,
            httpStatusCode: httpStatusCode,
            assessment: assessment,
            rawResponseBody: rawResponseBody,
            errorMessage: errorMessage,
            createdAt: createdAt
        )
    }
    #endif
}
