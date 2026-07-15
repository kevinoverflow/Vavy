import Foundation

struct PCM16WAVFile {
    static let sampleRate: UInt32 = 16_000
    static let channelCount: UInt16 = 1
    static let bitsPerSample: UInt16 = 16

    private static let bytesPerSample = Int(bitsPerSample / 8)
    private let pcmData: Data

    init(contentsOf fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw AppError.audioFileMissing
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            throw AppError.audioFileEmpty
        }

        try self.init(data: data)
    }

    init(data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 44,
              Self.asciiString(in: bytes, range: 0..<4) == "RIFF",
              Self.asciiString(in: bytes, range: 8..<12) == "WAVE" else {
            throw AppError.recordingFailed("The recording was not a valid WAV file.")
        }

        var offset = 12
        var format: WAVFormat?
        var audioBytes: Data?

        while offset + 8 <= bytes.count {
            let chunkID = Self.asciiString(in: bytes, range: offset..<(offset + 4))
            let chunkSize = Int(Self.readUInt32LE(bytes, at: offset + 4))
            let chunkStart = offset + 8
            guard chunkSize <= bytes.count - chunkStart else {
                throw AppError.recordingFailed("The WAV file was incomplete.")
            }
            let chunkEnd = chunkStart + chunkSize

            if chunkID == "fmt " {
                guard chunkSize >= 16 else {
                    throw AppError.recordingFailed("The WAV format chunk was invalid.")
                }

                format = WAVFormat(
                    audioFormat: Self.readUInt16LE(bytes, at: chunkStart),
                    channelCount: Self.readUInt16LE(bytes, at: chunkStart + 2),
                    sampleRate: Self.readUInt32LE(bytes, at: chunkStart + 4),
                    bitsPerSample: Self.readUInt16LE(bytes, at: chunkStart + 14)
                )
            } else if chunkID == "data", audioBytes == nil {
                audioBytes = Data(bytes[chunkStart..<chunkEnd])
            }

            let paddedChunkEnd = chunkEnd + (chunkSize % 2)
            offset = min(paddedChunkEnd, bytes.count)
        }

        guard let format,
              format.audioFormat == 1,
              format.sampleRate == Self.sampleRate,
              format.channelCount == Self.channelCount,
              format.bitsPerSample == Self.bitsPerSample,
              let audioBytes,
              !audioBytes.isEmpty,
              audioBytes.count.isMultiple(of: Self.bytesPerSample) else {
            throw AppError.recordingFailed("The recording must be 16 kHz mono 16-bit PCM WAV.")
        }

        pcmData = audioBytes
    }

    var samples: [Int16] {
        let bytes = [UInt8](pcmData)
        var values: [Int16] = []
        values.reserveCapacity(bytes.count / Self.bytesPerSample)

        for offset in stride(from: 0, to: bytes.count, by: Self.bytesPerSample) {
            values.append(Int16(bitPattern: Self.readUInt16LE(bytes, at: offset)))
        }

        return values
    }

    var durationMs: Int {
        let sampleCount = pcmData.count / Self.bytesPerSample
        return Int((Double(sampleCount) / Double(Self.sampleRate) * 1_000).rounded())
    }

    var canonicalData: Data {
        let byteRate = Self.sampleRate * UInt32(Self.channelCount) * UInt32(Self.bitsPerSample / 8)
        let blockAlignment = Self.channelCount * (Self.bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)

        var data = Data()
        data.reserveCapacity(44 + pcmData.count)
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36) + dataSize)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(Self.channelCount)
        data.appendLittleEndian(Self.sampleRate)
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlignment)
        data.appendLittleEndian(Self.bitsPerSample)
        data.appendASCII("data")
        data.appendLittleEndian(dataSize)
        data.append(pcmData)
        return data
    }

    func writeCanonical(to fileURL: URL) throws {
        try canonicalData.write(to: fileURL, options: .atomic)
    }

    private struct WAVFormat {
        let audioFormat: UInt16
        let channelCount: UInt16
        let sampleRate: UInt32
        let bitsPerSample: UInt16
    }

    private static func asciiString(in bytes: [UInt8], range: Range<Int>) -> String? {
        String(bytes: bytes[range], encoding: .ascii)
    }

    private static func readUInt16LE(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

private extension Data {
    mutating func appendASCII(_ value: String) {
        append(contentsOf: value.utf8)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            append(contentsOf: bytes)
        }
    }
}
