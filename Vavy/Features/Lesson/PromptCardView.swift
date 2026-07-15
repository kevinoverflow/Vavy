import SwiftUI

struct PromptCardView: View {
    let item: TrainingItem
    let index: Int
    let total: Int

    var body: some View {
        VStack(spacing: 18) {
            Text("\(index + 1) / \(total)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

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
}
