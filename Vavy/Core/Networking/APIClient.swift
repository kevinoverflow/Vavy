import Foundation

#if DEBUG
struct EvaluationAPIResponse {
    let result: AssessmentResult
    let statusCode: Int
    let rawResponseBody: String
}
#endif

struct APIClient {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL = AppConfig.backendBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchStarterLesson() async throws -> Lesson {
        let url = baseURL.appending(path: "/v1/lessons/starter")
        let (data, response) = try await perform(makeRequest(url: url))
        try validate(response: response, data: data)
        do {
            return try JSONDecoder().decode(Lesson.self, from: data)
        } catch {
            throw AppError.decodingFailed(decodeFailureDetail(error: error, data: data))
        }
    }

    func evaluateAttempt(
        itemID: String,
        audioFileURL: URL,
        audioQualityReport: AudioQualityReport? = nil,
        toneAnalysis: ToneAnalysisResult? = nil
    ) async throws -> AssessmentResult {
        let (data, _) = try await performEvaluationRequest(
            itemID: itemID,
            audioFileURL: audioFileURL,
            audioQualityReport: audioQualityReport,
            toneAnalysis: toneAnalysis
        )
        return try decodeAssessment(from: data)
    }

    #if DEBUG
    func evaluateAttemptDetailed(
        itemID: String,
        audioFileURL: URL,
        audioQualityReport: AudioQualityReport? = nil,
        toneAnalysis: ToneAnalysisResult? = nil
    ) async throws -> EvaluationAPIResponse {
        let (data, httpResponse) = try await performEvaluationRequest(
            itemID: itemID,
            audioFileURL: audioFileURL,
            audioQualityReport: audioQualityReport,
            toneAnalysis: toneAnalysis
        )

        return EvaluationAPIResponse(
            result: try decodeAssessment(from: data),
            statusCode: httpResponse.statusCode,
            rawResponseBody: String(data: data, encoding: .utf8) ?? "<non-UTF-8 response>"
        )
    }
    #endif

    private func performEvaluationRequest(
        itemID: String,
        audioFileURL: URL,
        audioQualityReport: AudioQualityReport?,
        toneAnalysis: ToneAnalysisResult?
    ) async throws -> (Data, HTTPURLResponse) {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw AppError.audioFileMissing
        }

        let audioData = try Data(contentsOf: audioFileURL)
        guard !audioData.isEmpty else {
            throw AppError.audioFileEmpty
        }

        var builder = MultipartFormDataBuilder()
        builder.addTextField(named: "item_id", value: itemID)
        if let audioQualityReport {
            builder.addTextField(
                named: "client_audio_features",
                value: audioQualityReport.clientFeaturesJSONString
            )
        }
        if let toneAnalysis {
            builder.addTextField(
                named: "client_tone_features",
                value: toneAnalysis.jsonString
            )
        }
        builder.addFileField(
            named: "audio",
            fileName: "attempt.wav",
            contentType: "audio/wav",
            fileData: audioData
        )

        let url = baseURL.appending(path: "/v1/attempts/evaluate")
        var request = makeRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(builder.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = builder.finalize()
        request.timeoutInterval = 60

        let (data, response) = try await perform(request)
        let httpResponse = try validate(response: response, data: data)
        return (data, httpResponse)
    }

    private func decodeAssessment(from data: Data) throws -> AssessmentResult {
        do {
            return try JSONDecoder().decode(AssessmentResult.self, from: data)
        } catch let appError as AppError {
            throw appError
        } catch {
            throw AppError.decodingFailed(decodeFailureDetail(error: error, data: data))
        }
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw AppError.networkUnavailable
        }
    }

    @discardableResult
    private func validate(response: URLResponse, data: Data) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw AppError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        return httpResponse
    }

    private func responseSnippet(from data: Data) -> String? {
        guard let rawValue = String(data: data, encoding: .utf8) else { return nil }
        let compactValue = rawValue.replacingOccurrences(of: "\n", with: " ")
        return String(compactValue.prefix(300))
    }

    private func decodeFailureDetail(error: Error, data: Data) -> String {
        let snippet = responseSnippet(from: data) ?? "No readable response body."
        return "\(error.localizedDescription) Response: \(snippet)"
    }
}
