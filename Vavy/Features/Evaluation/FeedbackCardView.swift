import SwiftUI

struct FeedbackCardView: View {
    let result: AssessmentResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let mainError = result.mainError, result.status != .passed {
                Label(mainError.type.displayName, systemImage: iconName(for: mainError.type))
                    .font(.headline)
                    .foregroundStyle(accentColor)
            }

            if let title = result.feedback?.title, !title.isEmpty {
                Text(title)
                    .font(.headline)
            }

            if let message = primaryMessage {
                Text(message)
                    .font(.body)
            }

            if let fix = result.feedback?.fix, !fix.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fix")
                        .font(.subheadline.weight(.semibold))
                    Text(fix)
                        .foregroundStyle(.secondary)
                }
            }

            if let drill = result.feedback?.drill, !drill.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Drill")
                        .font(.subheadline.weight(.semibold))
                    Text(drill.joined(separator: "  ·  "))
                        .font(.title3.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var primaryMessage: String? {
        result.feedback?.body ?? result.mainError?.message
    }

    private var accentColor: Color {
        switch result.status {
        case .passed:
            return Color(uiColor: .systemGreen)
        case .retryAudioQuality:
            return Color(uiColor: .systemOrange)
        case .backendError:
            return Color(uiColor: .systemOrange)
        case .notPassed:
            return Color(uiColor: .systemRed)
        }
    }

    private func iconName(for type: AssessmentErrorType) -> String {
        switch type {
        case .backendError:
            return "server.rack"
        case .audioQuality, .audioTooQuiet, .audioTooNoisy, .audioClipped:
            return "waveform.badge.exclamationmark"
        case .incompletePrompt:
            return "quote.bubble"
        case .toneConfusion:
            return "music.quarternote.3"
        default:
            return "target"
        }
    }
}
