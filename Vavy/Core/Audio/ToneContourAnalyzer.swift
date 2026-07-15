import Foundation

/// On-device pitch/tone-shape analysis for `tone_minimal_pair` items.
///
/// This is a heuristic v1: rule-based classification of a speaker-normalized
/// pitch contour into one of the six Vietnamese tones. It is not a trained
/// model (stays out of the "no PhoWhisper / no Core ML speech model"
/// constraint) and it is not guaranteed to be accurate — thresholds are
/// starting points that need tuning against real recordings. Hỏi and ngã in
/// particular are phonetically merged (no glottal break) for many speakers,
/// which this heuristic cannot fix; the backend decision rule is deliberately
/// asymmetric so a confident-but-wrong on-device verdict on that pair doesn't
/// hard-fail when Azure corroborates the expected tone.
struct ToneAnalysisResult: Codable, Equatable {
    let detectedTone: VietnameseTone?
    let confidence: Double
    /// 5-point speaker-normalized (semitone) pitch contour, quintile-averaged
    /// over voiced frames. `nil` at an index means that quintile had no
    /// voiced frames at all (a "gap") — itself a feature, not missing data:
    /// a mid-contour gap plus a late rise is a signal for ngã's glottal
    /// interruption; a trailing gap plus short voicing is a signal for nặng's
    /// checked/truncated tone.
    let contour: [Double?]
    let voicedFrameCount: Int
    let totalFrameCount: Int
    let durationMs: Int

    enum CodingKeys: String, CodingKey {
        case detectedTone = "detected_tone"
        case confidence
        case contour
        case voicedFrameCount = "voiced_frame_count"
        case totalFrameCount = "total_frame_count"
        case durationMs = "duration_ms"
    }

    var jsonString: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

struct ToneContourAnalyzer {
    private let sampleRate: Double
    private let frameLengthSamples: Int
    private let hopLengthSamples: Int
    private let pitchConfig = PitchEstimator.Config.default

    init(sampleRate: Double = Double(PCM16WAVFile.sampleRate)) {
        self.sampleRate = sampleRate
        // Frame length stays at 40ms — YIN needs at least ~2 periods of the
        // lowest frequency of interest (70Hz => ~14ms/period) to estimate
        // reliably. Hop is 5ms (finer than frame/4) purely for time
        // resolution: more, better-averaged frames per quintile bucket, and
        // a smoother live trace.
        self.frameLengthSamples = Int(sampleRate * 0.040)
        self.hopLengthSamples = Int(sampleRate * 0.005)
    }

    func analyze(samples: [Int16]) -> ToneAnalysisResult {
        let floatSamples = samples.map { Float($0) / 32_768.0 }
        let frames = makeFrames(from: floatSamples)
        let totalFrameCount = frames.count

        guard !frames.isEmpty else {
            return emptyResult(totalFrameCount: 0, sampleCount: samples.count)
        }

        var rawPitches: [Double?] = []
        rawPitches.reserveCapacity(frames.count)
        for frame in frames {
            let previousVoiced = rawPitches.last(where: { $0 != nil }) ?? nil
            rawPitches.append(PitchEstimator.estimate(frame: frame, sampleRate: sampleRate, previousHz: previousVoiced, config: pitchConfig))
        }

        let smoothedPitches = medianFilter3(rawPitches)
        let voicedHz = smoothedPitches.compactMap { $0 }
        let voicedFrameCount = voicedHz.count

        guard voicedFrameCount >= 3, let medianHz = PitchEstimator.median(voicedHz), medianHz > 0 else {
            return emptyResult(totalFrameCount: totalFrameCount, sampleCount: samples.count)
        }

        let semitones: [Double?] = smoothedPitches.map { hz in
            guard let hz else { return nil }
            return 12 * log2(hz / medianHz)
        }

        let contour = quintileSummary(trimSilence(semitones))
        let (tone, confidence) = classify(contour: contour, voicedFrameCount: voicedFrameCount, totalFrameCount: totalFrameCount)

        return ToneAnalysisResult(
            detectedTone: tone,
            confidence: confidence,
            contour: contour,
            voicedFrameCount: voicedFrameCount,
            totalFrameCount: totalFrameCount,
            durationMs: durationMs(sampleCount: samples.count)
        )
    }

    // MARK: - Framing

    private func makeFrames(from samples: [Float]) -> [[Float]] {
        guard samples.count >= frameLengthSamples, hopLengthSamples > 0 else { return [] }
        var frames: [[Float]] = []
        var start = 0
        while start + frameLengthSamples <= samples.count {
            frames.append(Array(samples[start..<(start + frameLengthSamples)]))
            start += hopLengthSamples
        }
        return frames
    }

    // MARK: - Smoothing

    private func medianFilter3(_ values: [Double?]) -> [Double?] {
        guard values.count >= 3 else { return values }
        var result = values
        for i in 1..<(values.count - 1) {
            guard values[i] != nil else { continue }
            let window = [values[i - 1], values[i], values[i + 1]].compactMap { $0 }
            guard window.count >= 2 else { continue }
            result[i] = PitchEstimator.median(window)
        }
        return result
    }

    // MARK: - Contour summary

    /// Drops leading/trailing frames with no pitch estimate before
    /// quintile-summarizing, so the 5-point contour is normalized to the
    /// span of actual speech rather than the raw recording — a short word
    /// like "ma" or "bá" leaves real dead air on both sides (tap-to-start
    /// lag, trailing silence before the user hits stop), and without this
    /// the outer quintiles land in that silence and come back `nil`,
    /// visibly shortening the plotted line relative to the reference
    /// contour. Internal gaps (e.g. ngã's glottal break) are untouched —
    /// only the outer silence is cut.
    private func trimSilence(_ semitones: [Double?]) -> [Double?] {
        guard let first = semitones.firstIndex(where: { $0 != nil }),
              let last = semitones.lastIndex(where: { $0 != nil }) else {
            return semitones
        }
        return Array(semitones[first...last])
    }

    private func quintileSummary(_ semitones: [Double?]) -> [Double?] {
        let quintileCount = 5
        var result = [Double?](repeating: nil, count: quintileCount)
        let frameCount = semitones.count
        guard frameCount > 0 else { return result }

        for q in 0..<quintileCount {
            let start = frameCount * q / quintileCount
            let end = max(start + 1, frameCount * (q + 1) / quintileCount)
            let slice = semitones[start..<min(end, frameCount)].compactMap { $0 }
            guard !slice.isEmpty else { continue }
            result[q] = slice.reduce(0, +) / Double(slice.count)
        }
        return result
    }

    // MARK: - Classification

    private func classify(contour: [Double?], voicedFrameCount: Int, totalFrameCount: Int) -> (VietnameseTone?, Double) {
        let voicedPoints = contour.compactMap { $0 }
        guard voicedPoints.count >= 3, let start = contour[0] ?? voicedPoints.first, let end = contour[4] ?? voicedPoints.last else {
            return (nil, 0)
        }

        let midPoints = [contour[1], contour[2], contour[3]]
        let midValues = midPoints.compactMap { $0 }
        let midAverage = midValues.isEmpty ? (start + end) / 2 : midValues.reduce(0, +) / Double(midValues.count)
        let hasMidGap = midPoints.contains(where: { $0 == nil })
        // voicedRatio (voiced frames vs. the whole recording, not the
        // trimmed contour) is the truncation signal for nặng: a short voiced
        // span relative to the full recording. contour[4]/[0] can no longer
        // be `nil` post-trim (the window's own edges are voiced by
        // construction), so there's no separate trailingGap case anymore.
        let voicedRatio = totalFrameCount > 0 ? Double(voicedFrameCount) / Double(totalFrameCount) : 0

        let slope = end - start
        let dip = min(start, end) - midAverage // positive when the middle dips below both ends
        let lateRise = end - midAverage

        let flatThreshold = 1.5
        let slopeThreshold = 2.5
        let dipThreshold = 1.5
        let sharpRiseThreshold = 3.0

        let tone: VietnameseTone
        let margin: Double

        if hasMidGap, dip > dipThreshold * 0.6, lateRise > sharpRiseThreshold {
            tone = .nga
            margin = min(dip - dipThreshold * 0.6, lateRise - sharpRiseThreshold)
        } else if midAverage < min(start, end) - 1.0, abs(slope) <= flatThreshold * 1.6, voicedRatio < 0.55 {
            tone = .nang
            margin = (min(start, end) - midAverage) - 1.0
        } else if dip > dipThreshold, !hasMidGap {
            tone = .hoi
            margin = dip - dipThreshold
        } else if slope > slopeThreshold {
            tone = .sac
            margin = slope - slopeThreshold
        } else if slope < -slopeThreshold {
            tone = .huyen
            margin = -slope - slopeThreshold
        } else if abs(slope) <= flatThreshold, dip <= dipThreshold {
            tone = .ngang
            margin = flatThreshold - abs(slope)
        } else {
            tone = slope >= 0 ? .sac : .huyen
            margin = 0
        }

        let marginConfidence = max(0, min(1, margin / 3))
        let confidence = (marginConfidence * 0.7) + (voicedRatio * 0.3)
        return (tone, max(0, min(1, confidence)))
    }

    // MARK: - Helpers

    private func durationMs(sampleCount: Int) -> Int {
        Int((Double(sampleCount) / sampleRate * 1_000).rounded())
    }

    private func emptyResult(totalFrameCount: Int, sampleCount: Int) -> ToneAnalysisResult {
        ToneAnalysisResult(
            detectedTone: nil,
            confidence: 0,
            contour: Array(repeating: nil, count: 5),
            voicedFrameCount: 0,
            totalFrameCount: totalFrameCount,
            durationMs: durationMs(sampleCount: sampleCount)
        )
    }
}
