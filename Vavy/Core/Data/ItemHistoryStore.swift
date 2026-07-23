import Combine
import Foundation

/// One graded attempt at a lesson item, kept for the user-facing per-item
/// progress view. Only genuinely judged attempts are recorded — not
/// `retryAudioQuality`/`backendError`, which aren't a real pronunciation
/// verdict (see AssessmentStatus.displayTitle).
struct ItemAttemptRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let itemID: String
    let createdAt: Date
    let status: AssessmentStatus
    let strictScore: Double?
}

/// Per-item rollup of `ItemAttemptRecord`s, used to render progress badges.
struct ItemHistorySummary: Equatable {
    let attemptCount: Int
    let passCount: Int
    let lastStatus: AssessmentStatus?
    let lastAttemptAt: Date?

    var hasAttempts: Bool { attemptCount > 0 }

    static let empty = ItemHistorySummary(attemptCount: 0, passCount: 0, lastStatus: nil, lastAttemptAt: nil)
}

/// Persists graded attempt outcomes per lesson item across launches, so
/// learners can see their pass/fail progress on a prompt rather than only
/// the result of their most recent take. Local-only: there is no
/// history-fetch endpoint in the backend API contract, so this is not
/// synced or backed up beyond the device.
@MainActor
final class ItemHistoryStore: ObservableObject {
    @Published private(set) var records: [ItemAttemptRecord] = []

    private let fileManager: FileManager
    private let historyFileURL: URL
    private let maximumRecordCount = 1_000

    init(fileManager: FileManager = .default, storageDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = storageDirectoryURL
            ?? supportDirectory.appendingPathComponent("VavyHistory", isDirectory: true)
        historyFileURL = directoryURL.appendingPathComponent("item_attempts.json")
        loadHistory()
    }

    func record(itemID: String, status: AssessmentStatus, strictScore: Double?, createdAt: Date = Date()) {
        let record = ItemAttemptRecord(id: UUID(), itemID: itemID, createdAt: createdAt, status: status, strictScore: strictScore)
        records.insert(record, at: 0)
        if records.count > maximumRecordCount {
            records.removeLast(records.count - maximumRecordCount)
        }
        persistHistory()
    }

    func summary(for itemID: String) -> ItemHistorySummary {
        let itemRecords = records.filter { $0.itemID == itemID }
        guard !itemRecords.isEmpty else { return .empty }
        return ItemHistorySummary(
            attemptCount: itemRecords.count,
            passCount: itemRecords.filter { $0.status == .passed }.count,
            lastStatus: itemRecords.first?.status,
            lastAttemptAt: itemRecords.first?.createdAt
        )
    }

    func clearHistory() {
        records = []
        persistHistory()
    }

    private func loadHistory() {
        guard fileManager.fileExists(atPath: historyFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: historyFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = try decoder.decode([ItemAttemptRecord].self, from: data)
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            records = []
        }
    }

    private func persistHistory() {
        do {
            try fileManager.createDirectory(at: historyFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(records).write(to: historyFileURL, options: .atomic)
        } catch {
            // Best-effort: losing progress history isn't worth surfacing an
            // error to the learner mid-lesson.
        }
    }
}
