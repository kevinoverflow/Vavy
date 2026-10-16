import SwiftUI

/// User-facing per-item pass/fail history for the whole lesson set — the
/// real progress record, as opposed to the raw request/response log in
/// AttemptDebugHistoryView (DEBUG-only, developer-facing).
struct LessonProgressView: View {
    let items: [TrainingItem]
    let historyStore: ItemHistoryStore
    let selectAction: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        selectAction(index)
                        dismiss()
                    } label: {
                        row(for: item, summary: historyStore.summary(for: item.id))
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(for item: TrainingItem, summary: ItemHistorySummary) -> some View {
        HStack(spacing: 12) {
            statusIcon(for: summary.lastStatus)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayText)
                    .font(.body.weight(.semibold))
                Text(item.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if summary.hasAttempts {
                Text("\(summary.passCount)/\(summary.attemptCount) passed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text("Not attempted")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private func statusIcon(for status: AssessmentStatus?) -> some View {
        let systemName: String
        let color: Color
        switch status {
        case .passed:
            systemName = "checkmark.circle.fill"
            color = Color(uiColor: .systemGreen)
        case .notPassed:
            systemName = "xmark.circle.fill"
            color = Color(uiColor: .systemRed)
        case .uncertain, .retryAudioQuality, .backendError, .none:
            systemName = "circle.dashed"
            color = Color(uiColor: .tertiaryLabel)
        }
        return Image(systemName: systemName).foregroundStyle(color)
    }
}

struct LessonProgressView_Previews: PreviewProvider {
    static var previews: some View {
        let store = ItemHistoryStore(storageDirectoryURL: FileManager.default.temporaryDirectory.appendingPathComponent("preview-progress"))
        let items = StarterLessonData.sampleLesson.items
        if let first = items.first {
            store.record(itemID: first.id, status: .passed, strictScore: 88)
            store.record(itemID: first.id, status: .notPassed, strictScore: 54)
        }
        return LessonProgressView(items: items, historyStore: store, selectAction: { _ in })
    }
}
