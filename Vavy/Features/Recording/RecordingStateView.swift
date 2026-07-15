import SwiftUI

struct RecordingStateView: View {
    let elapsedTime: TimeInterval
    /// Live pitch trace, only meaningful for `tone_minimal_pair` items — nil
    /// hides the pitch view entirely.
    var pitchPoints: [Double?]? = nil
    let cancelAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Recording")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .systemRed))
            Text(Self.formatter.string(from: elapsedTime) ?? "0:00")
                .font(.system(.title2, design: .monospaced).weight(.semibold))

            if let pitchPoints {
                VStack(alignment: .leading, spacing: 4) {
                    PitchWaveView(points: pitchPoints)
                    HStack {
                        Text("pitch, relative to your voice")
                        Spacer()
                        Text(voicedStateLabel(for: pitchPoints))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            Button(role: .cancel, action: cancelAction) {
                Label("Cancel", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func voicedStateLabel(for points: [Double?]) -> String {
        guard let last = points.last else { return "listening" }
        return last == nil ? "gap" : "voiced"
    }

    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()
}
