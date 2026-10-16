import Foundation
@testable import Vavy

/// Fixture loading and synthetic signals for analyzer tests.
@MainActor
enum TestAudio {
    static let sampleRate = Double(PCM16WAVFile.sampleRate)

    /// Loads a WAV fixture from the test bundle, falling back to the source tree so the same
    /// tests also run outside Xcode.
    static func fixtureSamples(named name: String) throws -> [Int16] {
        let bundleURL = Bundle(for: BundleToken.self).url(forResource: name, withExtension: "wav")
        // #filePath here is this file: VavyTests/Support/TestAudio.swift.
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).wav")
        return try PCM16WAVFile(contentsOf: bundleURL ?? sourceURL).samples
    }

    /// A harmonic tone whose fundamental glides linearly from `startHz` to `endHz`,
    /// with 150 ms of silence on each side. Synthetic, not speech: it checks the DSP
    /// mechanics, not tone-classification accuracy on real voices.
    static func glide(startHz: Double, endHz: Double, durationMs: Double, amplitude: Double = 0.3) -> [Int16] {
        let voicedCount = Int(durationMs / 1_000 * sampleRate)
        var samples = silence(ms: 150)
        var phase = 0.0
        for index in 0..<voicedCount {
            let t = Double(index) / Double(voicedCount)
            let hz = startHz + (endHz - startHz) * t
            phase += 2 * .pi * hz / sampleRate
            let envelope = min(1, Double(index) / 160, Double(voicedCount - index) / 160)
            let value = (sin(phase) + 0.5 * sin(2 * phase) + 0.25 * sin(3 * phase)) / 1.75
            samples.append(Int16((amplitude * envelope * value * 32_767).rounded()))
        }
        return samples + silence(ms: 150)
    }

    static func silence(ms: Double) -> [Int16] {
        [Int16](repeating: 0, count: Int(ms / 1_000 * sampleRate))
    }

    /// One 40 ms analysis frame (the analyzer's frame length) of a steady harmonic tone, normalized to -1...1.
    static func frame(hz: Double, amplitude: Float = 0.3) -> [Float] {
        let count = Int(sampleRate * 0.040)
        return (0..<count).map { index in
            let phase = 2 * .pi * hz * Double(index) / sampleRate
            return amplitude * Float((sin(phase) + 0.5 * sin(2 * phase) + 0.25 * sin(3 * phase)) / 1.75)
        }
    }

    static func scaled(_ samples: [Int16], by factor: Double) -> [Int16] {
        samples.map { Int16((Double($0) * factor).rounded(.towardZero)) }
    }

    private final class BundleToken {}
}
