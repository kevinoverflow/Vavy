import SwiftUI

struct LessonView: View {
    @StateObject private var viewModel: LessonViewModel
    #if DEBUG
    @State private var isShowingDebugAttempts = false
    #endif

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: LessonViewModel())
    }

    @MainActor
    init(viewModel: LessonViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingLesson && viewModel.lesson == nil {
                    LoadingView(message: "Loading starter lesson")
                } else if let item = viewModel.currentItem {
                    lessonContent(for: item)
                } else {
                    ErrorStateView(
                        title: "No lesson available",
                        message: "The starter lesson could not be loaded.",
                        retryAction: viewModel.loadLesson
                    )
                }
            }
            .navigationTitle("Vavy")
            .navigationBarTitleDisplayMode(.inline)
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingDebugAttempts = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .disabled(viewModel.isRecording || viewModel.isEvaluating)
                    .accessibilityLabel("Open debug attempts")
                    .accessibilityValue("\(viewModel.debugAttemptStore.entries.count) saved")
                }
            }
            #endif
        }
        #if DEBUG
        .sheet(isPresented: $isShowingDebugAttempts) {
            AttemptDebugHistoryView(store: viewModel.debugAttemptStore)
        }
        #endif
        .task {
            if viewModel.lesson == nil {
                viewModel.loadLesson()
            }
            viewModel.prepareRecording()
        }
        .onDisappear {
            viewModel.endRecordingSession()
        }
    }

    private func lessonContent(for item: TrainingItem) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                if let errorMessage = viewModel.errorMessage {
                    errorBanner(message: errorMessage)
                }

                if let lesson = viewModel.lesson {
                    Text(lesson.title)
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                PromptCardView(item: item, index: viewModel.currentIndex, total: viewModel.itemCount)

                HStack(spacing: 12) {
                    Button(action: viewModel.previousItem) {
                        Label("Previous", systemImage: "chevron.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.currentIndex == 0 || viewModel.isRecording || viewModel.isEvaluating)

                    Button(action: viewModel.nextItem) {
                        Label("Next", systemImage: "chevron.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.currentIndex >= viewModel.itemCount - 1 || viewModel.isRecording || viewModel.isEvaluating)
                }

                RecordButton(
                    isRecording: viewModel.isRecording,
                    isDisabled: viewModel.isEvaluating,
                    action: recordButtonTapped
                )
                .padding(.top, 8)

                if viewModel.isRecording {
                    RecordingStateView(
                        elapsedTime: viewModel.elapsedTime,
                        pitchPoints: item.category == .toneMinimalPair
                            ? viewModel.audioRecorder.livePitchTracker.semitonePoints
                            : nil,
                        cancelAction: viewModel.cancelRecording
                    )
                }

                if viewModel.isEvaluating {
                    LoadingView(message: "Evaluating pronunciation")
                        .frame(minHeight: 160)
                }

                if let result = viewModel.latestAssessment {
                    EvaluationView(
                        result: result,
                        toneAnalysis: viewModel.latestToneAnalysis,
                        expectedTone: item.expected.syllables.first?.tone,
                        tryAgainAction: viewModel.tryAgain,
                        nextPromptAction: viewModel.nextItem,
                        backToLessonAction: viewModel.backToLesson
                    )
                }

                #if DEBUG
                backendURLControl
                if let report = viewModel.latestAudioQualityReport {
                    audioQualityDebugView(report)
                }
                if let toneAnalysis = viewModel.latestToneAnalysis {
                    toneAnalysisDebugView(toneAnalysis)
                }
                #endif
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func recordButtonTapped() {
        if viewModel.isRecording {
            viewModel.stopRecordingAndEvaluate()
        } else {
            viewModel.startRecording()
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Button("Retry", action: viewModel.loadLesson)
                .font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    #if DEBUG
    private var backendURLControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Backend")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("http://localhost:3000", text: $viewModel.backendBaseURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.caption.monospaced())
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isRecording || viewModel.isEvaluating)

                Button(action: viewModel.applyBackendBaseURL) {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isRecording || viewModel.isEvaluating)
                .accessibilityLabel("Apply backend URL")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func audioQualityDebugView(_ report: AudioQualityReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Audio", systemImage: report.isUsable ? "waveform" : "waveform.badge.exclamationmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(report.isUsable ? Color(uiColor: .systemGreen) : Color(uiColor: .systemOrange))
                Spacer()
                Text(report.isUsable ? "usable" : "blocked")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(report.isUsable ? Color(uiColor: .systemGreen) : Color(uiColor: .systemOrange))
            }

            Text(report.debugSummary)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if !report.qualityFlags.isEmpty {
                Text("Flags: \(report.qualityFlags.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .systemOrange))
            }
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toneAnalysisDebugView(_ result: ToneAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("On-device tone", systemImage: "waveform.path")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(result.detectedTone.map { "\($0.displayName) (\(Int(result.confidence * 100))%)" } ?? "unknown")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(result.detectedTone == nil ? Color(uiColor: .systemOrange) : Color(uiColor: .systemGreen))
            }

            Text("contour: \(contourText(result.contour))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text("voiced \(result.voicedFrameCount)/\(result.totalFrameCount) frames · \(result.durationMs) ms")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func contourText(_ contour: [Double?]) -> String {
        contour.map { point in
            guard let point else { return "gap" }
            return String(format: "%.1f", point)
        }.joined(separator: ", ")
    }
    #endif
}

struct LessonView_Previews: PreviewProvider {
    static var previews: some View {
        LessonView(
            viewModel: LessonViewModel(
                apiClient: APIClient(),
                audioRecorder: AudioRecorder(),
                audioQualityAnalyzer: AudioQualityAnalyzer(),
                lesson: StarterLessonData.sampleLesson
            )
        )
    }
}
