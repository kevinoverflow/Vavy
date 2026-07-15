import Combine
import Foundation

/// Incremental, live version of `ToneContourAnalyzer`'s pitch tracking —
/// consumes audio samples as they arrive from the recording tap and
/// publishes a speaker-normalized (semitone) pitch trace for the live
/// recording UI.
///
/// Unlike the offline analyzer, the whole utterance isn't available yet, so
/// normalization is against a running median of the last ~50 voiced pitch
/// estimates rather than the whole-utterance median.
@MainActor
final class LivePitchTracker: ObservableObject {
    @Published private(set) var semitonePoints: [Double?] = []

    private let sampleRate: Double
    private let frameLength: Int
    private let hopLength: Int
    private let recentVoicedHzCap = 50

    private var sampleBuffer: [Float] = []
    private var previousHz: Double?
    private var recentVoicedHz: [Double] = []

    init(sampleRate: Double = Double(PCM16WAVFile.sampleRate)) {
        self.sampleRate = sampleRate
        // Matches ToneContourAnalyzer's framing (40ms frame, 5ms hop) so the
        // live trace and the offline post-recording analysis behave
        // consistently.
        self.frameLength = Int(sampleRate * 0.040)
        self.hopLength = Int(sampleRate * 0.005)
    }

    func reset() {
        semitonePoints = []
        sampleBuffer = []
        previousHz = nil
        recentVoicedHz = []
    }

    func ingest(_ samples: [Float]) {
        sampleBuffer.append(contentsOf: samples)

        while sampleBuffer.count >= frameLength {
            let frame = Array(sampleBuffer.prefix(frameLength))
            sampleBuffer.removeFirst(hopLength)

            guard let hz = PitchEstimator.estimate(frame: frame, sampleRate: sampleRate, previousHz: previousHz) else {
                semitonePoints.append(nil)
                continue
            }

            previousHz = hz
            recentVoicedHz.append(hz)
            if recentVoicedHz.count > recentVoicedHzCap {
                recentVoicedHz.removeFirst(recentVoicedHz.count - recentVoicedHzCap)
            }

            if let medianHz = PitchEstimator.median(recentVoicedHz), medianHz > 0 {
                semitonePoints.append(12 * log2(hz / medianHz))
            } else {
                semitonePoints.append(0)
            }
        }
    }
}
