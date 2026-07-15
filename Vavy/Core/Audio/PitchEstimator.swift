import Foundation

/// Shared YIN-style single-frame pitch estimator. Used by both
/// `ToneContourAnalyzer` (offline, full-utterance analysis after recording
/// finishes) and `LivePitchTracker` (incremental, while recording) so the
/// DSP implementation isn't duplicated between the two.
enum PitchEstimator {
    struct Config {
        var minFrequency: Double = 70
        var maxFrequency: Double = 400
        /// YIN absolute threshold for the cumulative mean normalized difference
        /// function. Lower = stricter voicing decision.
        var voicingThreshold: Double = 0.15
        /// Frame RMS below this (on a -1...1 normalized signal) is treated as
        /// silence regardless of what YIN reports, to avoid pitch-tracking noise.
        var minFrameRMS: Double = 0.01

        static let `default` = Config()
    }

    /// Estimates the fundamental frequency of one frame via a YIN-style
    /// cumulative mean normalized difference function, with a continuity
    /// constraint against the previous voiced frame's pitch (prefers the
    /// candidate closest in semitone distance to `previousHz` over always
    /// taking the strongest dip) to suppress octave errors on
    /// creaky/glottalized voice.
    static func estimate(frame: [Float], sampleRate: Double, previousHz: Double?, config: Config = .default) -> Double? {
        let rms = sqrt(frame.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(frame.count))
        guard rms >= config.minFrameRMS else { return nil }

        let minLag = max(2, Int((sampleRate / config.maxFrequency).rounded(.down)))
        let maxLag = Int((sampleRate / config.minFrequency).rounded(.up))
        guard maxLag < frame.count, minLag < maxLag else { return nil }

        var difference = [Double](repeating: 0, count: maxLag + 1)
        for tau in 1...maxLag {
            var sum = 0.0
            for j in 0..<(frame.count - tau) {
                let delta = Double(frame[j]) - Double(frame[j + tau])
                sum += delta * delta
            }
            difference[tau] = sum
        }

        var cmndf = [Double](repeating: 1, count: maxLag + 1)
        var runningSum = 0.0
        for tau in 1...maxLag {
            runningSum += difference[tau]
            cmndf[tau] = runningSum > 0 ? difference[tau] * Double(tau) / runningSum : 1
        }

        var candidates: [(tau: Int, value: Double)] = []
        for tau in minLag...maxLag {
            guard cmndf[tau] < config.voicingThreshold else { continue }
            let prev = tau > minLag ? cmndf[tau - 1] : cmndf[tau]
            let next = tau < maxLag ? cmndf[tau + 1] : cmndf[tau]
            if cmndf[tau] <= prev && cmndf[tau] <= next {
                candidates.append((tau, cmndf[tau]))
            }
        }

        guard !candidates.isEmpty else { return nil }

        let chosen: (tau: Int, value: Double)
        if let previousHz {
            chosen = candidates.min { a, b in
                let freqA = sampleRate / Double(a.tau)
                let freqB = sampleRate / Double(b.tau)
                return abs(log2(freqA / previousHz)) < abs(log2(freqB / previousHz))
            }!
        } else {
            chosen = candidates.min { $0.value < $1.value }!
        }

        // Parabolic interpolation around the chosen integer-lag minimum gives
        // a fractional (sub-sample) lag estimate — finer pitch resolution
        // without needing a higher sample rate. At 16kHz, integer-lag
        // quantization alone spaces adjacent achievable frequencies ~2-6Hz
        // apart in the 200-300Hz range (roughly a quarter-semitone step),
        // which this removes.
        let refinedTau = parabolicRefine(cmndf: cmndf, tau: chosen.tau)
        return sampleRate / refinedTau
    }

    /// Fits a parabola through the CMNDF values around `tau` and returns the
    /// fractional lag at its minimum. Falls back to the integer `tau` at the
    /// array edges or when the three points are collinear.
    private static func parabolicRefine(cmndf: [Double], tau: Int) -> Double {
        guard tau > 0, tau < cmndf.count - 1 else { return Double(tau) }
        let y0 = cmndf[tau - 1]
        let y1 = cmndf[tau]
        let y2 = cmndf[tau + 1]
        let denominator = y0 - 2 * y1 + y2
        guard denominator != 0 else { return Double(tau) }
        let delta = 0.5 * (y0 - y2) / denominator
        return Double(tau) + max(-1, min(1, delta))
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
