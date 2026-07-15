import AVFoundation
import Foundation

/// Converts and writes live `AVAudioEngine` tap buffers to a WAV file, and
/// hands back the converted samples for live pitch analysis.
///
/// Deliberately **not** `@MainActor`: the engine tap callback runs on a
/// real-time audio thread and must not synchronously call into MainActor-
/// isolated code. All conversion/write work happens on a private serial
/// queue, invoked with `.sync` from the tap callback — this keeps the
/// callback itself synchronous (same real-time-thread semantics as calling
/// it inline) while giving the caller a way to guarantee drain: after
/// removing the tap, call `drainAndClose()` before touching the file, so any
/// in-flight write from the last callback has finished.
final class AudioTapWriter {
    private let converter: AVAudioConverter
    private let audioFile: AVAudioFile
    private let targetFormat: AVAudioFormat
    private let queue = DispatchQueue(label: "com.vavy.audioTapWriter")

    init(inputFormat: AVAudioFormat, outputURL: URL, targetSettings: [String: Any]) throws {
        guard let targetFormat = AVAudioFormat(settings: targetSettings) else {
            throw AppError.recordingFailed("The microphone could not be prepared. Try again.")
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AppError.recordingFailed("The microphone could not be prepared. Try again.")
        }
        // Take the first input channel explicitly rather than relying on
        // implicit downmix behavior when the hardware input is stereo.
        converter.channelMap = [0]

        self.converter = converter
        self.targetFormat = targetFormat
        // Without an explicit commonFormat/interleaved, AVAudioFile defaults
        // its processingFormat to Float32 non-interleaved regardless of what
        // the on-disk settings say — while the output buffers here are Int16
        // interleaved (matching targetFormat). write(from:) requires the
        // buffer's format to equal processingFormat exactly; a mismatch here
        // (especially interleaved vs non-interleaved, a different memory
        // layout entirely) is what was tripping a hard Core Audio abort
        // rather than a catchable error. Pin processingFormat to match
        // targetFormat exactly.
        self.audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: targetSettings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
    }

    /// Converts and writes one tap buffer, looping until the converter has
    /// fully drained it (a single call can leave trailing samples
    /// unconverted at the ~3:1, 48kHz->16kHz downsample ratio). Returns the
    /// converted mono samples (normalized to -1...1) for live pitch use, or
    /// `nil` on failure — non-fatal, the caller just skips this chunk.
    func process(buffer: AVAudioPCMBuffer) -> [Float]? {
        queue.sync {
            var collected: [Float] = []
            var inputConsumed = false
            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16

            drainLoop: while true {
                guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
                    break drainLoop
                }

                var conversionError: NSError?
                let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                    if inputConsumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    inputConsumed = true
                    outStatus.pointee = .haveData
                    return buffer
                }

                guard conversionError == nil else { break drainLoop }

                if outputBuffer.frameLength > 0 {
                    guard (try? audioFile.write(from: outputBuffer)) != nil else { break drainLoop }
                    if let int16Data = outputBuffer.int16ChannelData {
                        let samples = UnsafeBufferPointer(start: int16Data[0], count: Int(outputBuffer.frameLength))
                        collected.append(contentsOf: samples.map { Float($0) / 32_768.0 })
                    }
                }

                switch status {
                case .haveData:
                    continue drainLoop
                case .inputRanDry, .endOfStream, .error:
                    break drainLoop
                @unknown default:
                    break drainLoop
                }
            }

            return collected.isEmpty ? nil : collected
        }
    }

    /// Blocks until any in-flight `process(buffer:)` call has completed.
    /// Call after removing the engine tap and before reading the finished
    /// file from disk.
    func drainAndClose() {
        queue.sync {}
    }
}
