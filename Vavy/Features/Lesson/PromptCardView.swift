import SwiftUI

struct PromptCardView: View {
    let item: TrainingItem
    let index: Int
    let total: Int
    var historySummary: ItemHistorySummary = .empty

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("\(index + 1) / \(total)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if historySummary.hasAttempts {
                    historyBadge
                }
            }

            Text(item.displayText)
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.45)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                Text(metadataLine)
                    .font(.headline)
                if let tone = item.expected.syllables.first?.tone {
                    Text("\(tone.displayName) tone")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var metadataLine: String {
        "\(item.category.displayName) · \(item.targetDialect.displayName) · Level \(item.difficulty)"
    }

    private var historyBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: historySummary.lastStatus == .passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(historySummary.lastStatus == .passed ? Color(uiColor: .systemGreen) : Color(uiColor: .systemRed))
            Text("\(historySummary.passCount)/\(historySummary.attemptCount) passed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
