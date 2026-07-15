import Foundation

struct AudioQualityReport: Equatable {
    let durationMs: Int
    let peakAmplitude: Float
    let rms: Float
    let clippingRatio: Float
    let isTooShort: Bool
    let isTooLong: Bool
    let isTooQuiet: Bool
    let isClipped: Bool
    let isUsable: Bool

    enum CodingKeys: String, CodingKey {
        case durationMs = "duration_ms"
        case rms
        case peak = "peak"
        case clippingRatio = "clipping_ratio"
    }

    var clientFeaturesJSONString: String {
        let payload: [String: Any] = [
            CodingKeys.durationMs.rawValue: durationMs,
            CodingKeys.rms.rawValue: rms,
            CodingKeys.peak.rawValue: peakAmplitude,
            CodingKeys.clippingRatio.rawValue: clippingRatio
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return string
    }

    var debugSummary: String {
        [
            "\(durationMs) ms",
            "rms \(Self.format(rms))",
            "peak \(Self.format(peakAmplitude))",
            "clip \(Self.format(clippingRatio))"
        ].joined(separator: " · ")
    }

    var qualityFlags: [String] {
        var flags: [String] = []
        if isTooShort { flags.append("short") }
        if isTooLong { flags.append("long") }
        if isTooQuiet { flags.append("quiet") }
        if isClipped { flags.append("clipped") }
        return flags
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.3f", value)
    }
}

struct AudioQualityAnalyzer {
    struct Thresholds {
        var tooShortMs = 350
        var tooLongMs = 10_000
        // Keep the client gate lenient. The backend still makes the final quality decision.
        var tooQuietRMS: Float = 0.004
        var tooQuietPeak: Float = 0.020
        var clippingAmplitude: Float = 0.98
        var clippingRatio: Float = 0.01
    }

    var thresholds = Thresholds()

    func analyze(fileURL: URL) throws -> AudioQualityReport {
        let wav = try PCM16WAVFile(contentsOf: fileURL)
        let samples = wav.samples
        guard !samples.isEmpty else {
            throw AppError.audioFileEmpty
        }

        let durationMs = wav.durationMs
        var peak: Float = 0
        var sumSquares: Double = 0
        var clippedSamples = 0

        for sample in samples {
            let amplitude = Float(abs(Int(sample))) / 32_768
            peak = max(peak, amplitude)
            sumSquares += Double(amplitude * amplitude)

            if amplitude >= thresholds.clippingAmplitude {
                clippedSamples += 1
            }
        }

        let rms = Float(sqrt(sumSquares / Double(samples.count)))
        let clippingRatio = Float(clippedSamples) / Float(samples.count)
        let isTooShort = durationMs < thresholds.tooShortMs
        let isTooLong = durationMs > thresholds.tooLongMs
        let isTooQuiet = rms < thresholds.tooQuietRMS && peak < thresholds.tooQuietPeak
        let isClipped = clippingRatio > thresholds.clippingRatio

        return AudioQualityReport(
            durationMs: durationMs,
            peakAmplitude: peak,
            rms: rms,
            clippingRatio: clippingRatio,
            isTooShort: isTooShort,
            isTooLong: isTooLong,
            isTooQuiet: isTooQuiet,
            isClipped: isClipped,
            isUsable: !isTooShort && !isTooLong && !isTooQuiet && !isClipped
        )
    }

}
