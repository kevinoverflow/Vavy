import Foundation

// Runs the app's own ToneContourAnalyzer over WAV files and prints one JSON line per file:
//   {"audio_path": "/abs/path.wav", "client_tone_features": { ...ToneAnalysisResult... }}
// This is the input format for the backend's `npm run eval -- --client-tone <file>`.
// Built by ../extract-tone-features.sh from the app sources; it contains no analyzer code itself.

let analyzer = ToneContourAnalyzer()
var failures = 0

for argument in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: argument).standardizedFileURL
    do {
        let samples = try PCM16WAVFile(contentsOf: url).samples
        let features = try JSONSerialization.jsonObject(with: Data(analyzer.analyze(samples: samples).jsonString.utf8))
        let line = try JSONSerialization.data(
            withJSONObject: ["audio_path": url.path, "client_tone_features": features],
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        print(String(decoding: line, as: UTF8.self))
    } catch {
        failures += 1
        let reason = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        FileHandle.standardError.write(Data("skipped \(url.path): \(reason)\n".utf8))
    }
}

exit(failures == 0 ? 0 : 1)
