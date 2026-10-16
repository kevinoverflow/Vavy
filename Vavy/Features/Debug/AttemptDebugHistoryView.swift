#if DEBUG
import SwiftUI

struct AttemptDebugHistoryView: View {
    @ObservedObject var store: AttemptDebugStore
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingClearConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableView(
                        "No debug attempts",
                        systemImage: "waveform",
                        description: Text("Recorded attempts will appear here.")
                    )
                } else {
                    List {
                        if let storageError = store.storageError {
                            Label(storageError, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }

                        ForEach(store.entries) { entry in
                            NavigationLink {
                                AttemptDebugDetailView(
                                    entry: entry,
                                    audioFileURL: store.audioURL(for: entry)
                                )
                            } label: {
                                AttemptDebugRow(entry: entry)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Debug attempts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                if !store.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            isShowingClearConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Clear debug attempts")
                    }
                }
            }
            .confirmationDialog(
                "Clear all debug attempts?",
                isPresented: $isShowingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Attempts", role: .destructive, action: store.clearHistory)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes the retained logs and audio files.")
            }
        }
    }
}

private struct AttemptDebugRow: View {
    let entry: AttemptDebugEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.expectedText)
                        .font(.headline)
                    Spacer()
                    if entry.audioFileName != nil {
                        Image(systemName: "speaker.wave.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Audio retained")
                    }
                }

                Text(entry.statusText.replacingOccurrences(of: "_", with: " "))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(statusColor)

                Text(entry.itemID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(entry.createdAt.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var statusColor: Color {
        switch entry.assessment?.status {
        case .passed:
            return Color(uiColor: .systemGreen)
        case .notPassed:
            return Color(uiColor: .systemRed)
        case .uncertain, .retryAudioQuality, .backendError, .none:
            return Color(uiColor: .systemOrange)
        }
    }

    private var statusIcon: String {
        switch entry.assessment?.status {
        case .passed:
            return "checkmark.circle.fill"
        case .notPassed:
            return "xmark.circle.fill"
        case .uncertain:
            return "questionmark.circle.fill"
        case .retryAudioQuality:
            return "waveform.badge.exclamationmark"
        case .backendError, .none:
            return "exclamationmark.circle.fill"
        }
    }
}

private struct AttemptDebugDetailView: View {
    let entry: AttemptDebugEntry
    let audioFileURL: URL?

    var body: some View {
        List {
            Section("Attempt") {
                LabeledContent("Prompt", value: entry.expectedText)
                LabeledContent("Item ID", value: entry.itemID)
                LabeledContent("Status", value: entry.statusText)
                LabeledContent("Source", value: entry.source.rawValue)
                if let attemptID = entry.attemptID {
                    LabeledContent("Attempt ID", value: attemptID)
                        .textSelection(.enabled)
                }
                LabeledContent(
                    "Created",
                    value: entry.createdAt.formatted(date: .abbreviated, time: .standard)
                )
            }

            Section("Audio") {
                if let audioFileURL {
                    DebugAudioPlaybackView(fileURL: audioFileURL)
                    if let audioByteCount = entry.audioByteCount {
                        LabeledContent("File size", value: ByteCountFormatter.string(
                            fromByteCount: Int64(audioByteCount),
                            countStyle: .file
                        ))
                    }
                } else {
                    Label("No retained recording", systemImage: "speaker.slash")
                        .foregroundStyle(.secondary)
                }
            }

            if entry.durationMs != nil {
                Section("Local audio quality") {
                    if let durationMs = entry.durationMs {
                        LabeledContent("Duration", value: "\(durationMs) ms")
                    }
                    if let rms = entry.rms {
                        LabeledContent("RMS", value: format(rms))
                    }
                    if let peakAmplitude = entry.peakAmplitude {
                        LabeledContent("Peak", value: format(peakAmplitude))
                    }
                    if let clippingRatio = entry.clippingRatio {
                        LabeledContent("Clipping ratio", value: format(clippingRatio))
                    }
                    LabeledContent(
                        "Flags",
                        value: entry.qualityFlags.isEmpty ? "none" : entry.qualityFlags.joined(separator: ", ")
                    )
                }
            }

            if let assessment = entry.assessment {
                Section("Scores") {
                    ScoreRowView(label: "Pronunciation", score: assessment.scores?.pronunciation)
                    ScoreRowView(label: "Accuracy", score: assessment.scores?.accuracy)
                    ScoreRowView(label: "Completeness", score: assessment.scores?.completeness)
                    ScoreRowView(label: "Fluency", score: assessment.scores?.fluency)
                    ScoreRowView(label: "Strict score", score: assessment.strictScore)
                }
            }

            Section("Client log") {
                Text(entry.logText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle(entry.expectedText)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func format(_ value: Float) -> String {
        String(format: "%.5f", value)
    }
}

private struct DebugAudioPlaybackView: View {
    let fileURL: URL
    @StateObject private var player = DebugAudioPlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(action: player.togglePlayback) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(player.duration <= 0)
                .accessibilityLabel(player.isPlaying ? "Pause recording" : "Play recording")

                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 0.01)
                )
                .disabled(player.duration <= 0)
            }

            HStack {
                Text(formatTime(player.currentTime))
                Spacer()
                Text(formatTime(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            if let errorMessage = player.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .onAppear {
            player.load(fileURL: fileURL)
        }
        .onDisappear {
            player.stop()
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let seconds = max(0, Int(time.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
#endif
