import SwiftUI

struct ScoreRowView: View {
    let label: String
    let score: Double?

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(scoreText)
                .font(.body.monospacedDigit().weight(.semibold))
        }
        .padding(.vertical, 4)
    }

    private var scoreText: String {
        ScoreFormatter.string(from: score)
    }
}

enum ScoreFormatter {
    static func string(from score: Double?) -> String {
        guard let score else { return "—" }

        return score.formatted(
            .number
                .grouping(.never)
                .precision(.fractionLength(score.rounded() == score ? 0 : 1))
        )
    }
}
