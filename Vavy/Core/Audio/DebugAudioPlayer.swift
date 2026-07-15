#if DEBUG
import AVFoundation
import Combine
import Foundation

@MainActor
final class DebugAudioPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var errorMessage: String?

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(fileURL: URL) {
        stop()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            errorMessage = "The retained recording could not be found."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: fileURL)
            guard player.prepareToPlay() else {
                throw AppError.recordingFailed("The recording could not be prepared for playback.")
            }

            self.player = player
            duration = player.duration
            currentTime = 0
            errorMessage = nil
        } catch {
            errorMessage = "Could not play this recording: \(error.localizedDescription)"
        }
    }

    func togglePlayback() {
        guard let player else { return }

        if player.isPlaying {
            player.pause()
            isPlaying = false
            currentTime = player.currentTime
            stopTimer()
            return
        }

        if player.currentTime >= max(0, duration - 0.05) {
            player.currentTime = 0
            currentTime = 0
        }

        guard player.play() else {
            errorMessage = "Playback could not start."
            return
        }

        isPlaying = true
        errorMessage = nil
        startTimer()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clampedTime = min(max(0, time), duration)
        player.currentTime = clampedTime
        currentTime = clampedTime
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        stopTimer()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player else { return }
                currentTime = player.currentTime

                if !player.isPlaying {
                    isPlaying = false
                    currentTime = min(duration, player.currentTime)
                    stopTimer()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
#endif
