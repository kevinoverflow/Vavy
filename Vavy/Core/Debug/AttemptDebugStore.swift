#if DEBUG
import Combine
import Foundation

enum AttemptDebugSource: String, Codable {
    case localAudioQuality = "local_audio_quality"
    case backendResponse = "backend_response"
    case requestError = "request_error"
    case clientError = "client_error"
}

struct AttemptDebugEntry: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let source: AttemptDebugSource
    let itemID: String
    let expectedText: String
    let backendBaseURL: String
    let audioFileName: String?
    let audioByteCount: Int?
    let durationMs: Int?
    let peakAmplitude: Float?
    let rms: Float?
    let clippingRatio: Float?
    let qualityFlags: [String]
    let detectedTone: VietnameseTone?
    let toneConfidence: Double?
    let toneContour: [Double?]?
    let requestDurationMs: Int?
    let httpStatusCode: Int?
    let assessment: AssessmentResult?
    let rawResponseBody: String?
    let errorMessage: String?
    let storageNote: String?

    var statusText: String {
        assessment?.status.rawValue ?? "request_error"
    }

    var attemptID: String? {
        assessment?.attemptID
    }

    var logText: String {
        var lines = [
            "timestamp: \(Self.timestampFormatter.string(from: createdAt))",
            "source: \(source.rawValue)",
            "backend: \(backendBaseURL)",
            "request: POST /v1/attempts/evaluate",
            "item_id: \(itemID)",
            "expected_text: \(expectedText)"
        ]

        if let audioFileName {
            lines.append("audio: \(audioFileName)")
        }
        if let audioByteCount {
            lines.append("audio_bytes: \(audioByteCount)")
        }
        if let durationMs, let rms, let peakAmplitude, let clippingRatio {
            lines.append(
                "client_audio_features: {\"duration_ms\":\(durationMs),\"rms\":\(Self.format(rms)),\"peak\":\(Self.format(peakAmplitude)),\"clipping_ratio\":\(Self.format(clippingRatio))}"
            )
        }
        if !qualityFlags.isEmpty {
            lines.append("quality_flags: \(qualityFlags.joined(separator: ", "))")
        }
        if let detectedTone, let toneConfidence {
            let contourText = (toneContour ?? []).map { $0.map { Self.format(Float($0)) } ?? "gap" }.joined(separator: ", ")
            lines.append(
                "client_tone_features: {\"detected_tone\":\"\(detectedTone.rawValue)\",\"confidence\":\(Self.format(Float(toneConfidence)))} contour: [\(contourText)]"
            )
        }
        if let requestDurationMs {
            lines.append("request_duration_ms: \(requestDurationMs)")
        }
        if let httpStatusCode {
            lines.append("http_status: \(httpStatusCode)")
        }
        if let attemptID {
            lines.append("attempt_id: \(attemptID)")
        }
        lines.append("status: \(statusText)")

        if let errorMessage {
            lines.append("error: \(errorMessage)")
        }
        if let storageNote {
            lines.append("storage_note: \(storageNote)")
        }

        if let rawResponseBody {
            lines.append("\nresponse:\n\(Self.prettyJSON(rawResponseBody))")
        } else if let assessment,
                  let data = try? Self.assessmentEncoder.encode(assessment),
                  let encodedAssessment = String(data: data, encoding: .utf8) {
            lines.append("\nlocal_result:\n\(encodedAssessment)")
        }

        return lines.joined(separator: "\n")
    }

    private static let timestampFormatter = ISO8601DateFormatter()

    private static let assessmentEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static func format(_ value: Float) -> String {
        String(format: "%.5f", value)
    }

    private static func prettyJSON(_ value: String) -> String {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return value
        }

        return prettyString
    }
}

@MainActor
final class AttemptDebugStore: ObservableObject {
    @Published private(set) var entries: [AttemptDebugEntry] = []
    @Published private(set) var storageError: String?

    private let fileManager: FileManager
    private let directoryURL: URL
    private let historyFileURL: URL
    private let maximumEntryCount = 50

    init(fileManager: FileManager = .default, storageDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directoryURL = storageDirectoryURL
            ?? cacheDirectory.appendingPathComponent("VavyDebugAttempts", isDirectory: true)
        historyFileURL = directoryURL.appendingPathComponent("history.json")
        loadHistory()
    }

    func record(
        source: AttemptDebugSource,
        item: TrainingItem,
        backendBaseURL: URL,
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
        let id = UUID()
        let retainedAudio = retainAudio(from: audioFileURL, entryID: id)
        let entry = AttemptDebugEntry(
            id: id,
            createdAt: createdAt,
            source: source,
            itemID: item.id,
            expectedText: item.displayText,
            backendBaseURL: backendBaseURL.absoluteString,
            audioFileName: retainedAudio.fileName,
            audioByteCount: retainedAudio.byteCount,
            durationMs: audioQualityReport?.durationMs,
            peakAmplitude: audioQualityReport?.peakAmplitude,
            rms: audioQualityReport?.rms,
            clippingRatio: audioQualityReport?.clippingRatio,
            qualityFlags: audioQualityReport?.qualityFlags ?? [],
            detectedTone: toneAnalysis?.detectedTone,
            toneConfidence: toneAnalysis?.confidence,
            toneContour: toneAnalysis?.contour,
            requestDurationMs: requestDurationMs,
            httpStatusCode: httpStatusCode,
            assessment: assessment,
            rawResponseBody: rawResponseBody,
            errorMessage: errorMessage,
            storageNote: retainedAudio.errorMessage
        )

        entries.insert(entry, at: 0)
        trimHistoryIfNeeded()
        persistHistory()
    }

    func audioURL(for entry: AttemptDebugEntry) -> URL? {
        guard let audioFileName = entry.audioFileName else { return nil }
        let url = directoryURL.appendingPathComponent(audioFileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func clearHistory() {
        do {
            if fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.removeItem(at: directoryURL)
            }
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            entries = []
            storageError = nil
            persistHistory()
        } catch {
            storageError = "Could not clear debug attempts: \(error.localizedDescription)"
        }
    }

    private func retainAudio(from sourceURL: URL?, entryID: UUID) -> (fileName: String?, byteCount: Int?, errorMessage: String?) {
        guard let sourceURL else { return (nil, nil, nil) }

        let attributes = try? fileManager.attributesOfItem(atPath: sourceURL.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.intValue
        let fileName = "attempt-\(entryID.uuidString).wav"
        let destinationURL = directoryURL.appendingPathComponent(fileName)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return (fileName, byteCount, nil)
        } catch {
            return (nil, byteCount, "Audio copy failed: \(error.localizedDescription)")
        }
    }

    private func loadHistory() {
        guard fileManager.fileExists(atPath: historyFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: historyFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([AttemptDebugEntry].self, from: data)
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            storageError = "Could not read debug attempt history: \(error.localizedDescription)"
        }
    }

    private func persistHistory() {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries).write(to: historyFileURL, options: .atomic)
            storageError = nil
        } catch {
            storageError = "Could not save debug attempt history: \(error.localizedDescription)"
        }
    }

    private func trimHistoryIfNeeded() {
        guard entries.count > maximumEntryCount else { return }
        let removedEntries = entries.suffix(from: maximumEntryCount)
        entries = Array(entries.prefix(maximumEntryCount))

        for entry in removedEntries {
            guard let audioFileName = entry.audioFileName else { continue }
            try? fileManager.removeItem(at: directoryURL.appendingPathComponent(audioFileName))
        }
    }
}
#endif
