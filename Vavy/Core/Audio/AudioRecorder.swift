import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var recordedFileURL: URL?
    @Published private(set) var elapsedTime: TimeInterval = 0

    var maximumDurationReachedHandler: (() -> Void)?

    /// Live, speaker-normalized pitch trace while recording. Populated from
    /// the same engine tap that writes the file — see AudioTapWriter.
    let livePitchTracker = LivePitchTracker()

    private let permissionService: MicrophonePermissionService
    /// A single, persistent engine instance — never recreated per recording.
    /// Recreating it would reintroduce IO-unit warm-up latency at this layer,
    /// the same class of bug the session-reuse fix eliminated at the
    /// AVAudioSession layer.
    private let engine = AVAudioEngine()
    private var tapWriter: AudioTapWriter?
    private var currentFileURL: URL?
    private var timer: Timer?
    private var recordingStartedAt: Date?
    private let maxDuration: TimeInterval = 10
    private var isSessionActive = false

    override init() {
        self.permissionService = MicrophonePermissionService()
        super.init()
    }

    init(permissionService: MicrophonePermissionService) {
        self.permissionService = permissionService
        super.init()
    }

    /// Activates the audio session ahead of time so the hardware is already warm
    /// by the time the user taps record. Switching an AVAudioSession category and
    /// activating it triggers a real hardware route setup with noticeable latency
    /// (silence at the start of the recording); doing this early, once, avoids
    /// paying that cost on every tap.
    func prepareSession() async throws {
        guard !isSessionActive else { return }

        let granted = await permissionService.requestPermission()
        guard granted else {
            throw AppError.microphonePermissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setPreferredSampleRate(Double(PCM16WAVFile.sampleRate))
            try session.setActive(true)
            // AVAudioEngine's IO nodes are created lazily on first access. If
            // prepare() is called before anything has touched inputNode, the
            // engine's rendering graph is still completely empty and it
            // crashes with "required condition is false: inputNode !=
            // nullptr || outputNode != nullptr". Touching inputNode first
            // forces that lazy creation.
            _ = engine.inputNode
            // Warms up the engine's IO unit too, so switching to AVAudioEngine
            // (needed for the live pitch tap) doesn't reintroduce the same
            // warm-up latency at this layer.
            engine.prepare()
            isSessionActive = true
        } catch {
            throw AppError.recordingFailed("The microphone could not be prepared. Try again.")
        }
    }

    /// Releases the audio session and stops the engine. Call when leaving the
    /// recording screen entirely, not between individual recordings.
    func endSession() {
        guard isSessionActive else { return }
        engine.stop()
        deactivateAudioSession()
        isSessionActive = false
    }

    func startRecording() async throws {
        guard !isRecording else { return }

        try await prepareSession()
        livePitchTracker.reset()

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("viet-tutor-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        if let previousFileURL = recordedFileURL {
            try? FileManager.default.removeItem(at: previousFileURL)
            recordedFileURL = nil
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw AppError.recordingFailed("The microphone could not be prepared. Try again.")
        }

        do {
            let writer = try AudioTapWriter(inputFormat: inputFormat, outputURL: fileURL, targetSettings: settings)
            tapWriter = writer

            // Weakly captured: AVAudioFile has no public close() method, only
            // deinit finalizes its WAV header (patches in the real chunk
            // sizes). If the tap closure held `writer` strongly, it could
            // keep AudioTapWriter (and its AVAudioFile) alive past
            // `tapWriter = nil` below — Core Audio doesn't guarantee it
            // releases a removed tap's closure synchronously — so the file
            // read back in stopRecording() could still have an
            // unfinalized/incomplete header. Making `tapWriter` the sole
            // strong owner means nil-ing it is the definitive dealloc point.
            let tracker = livePitchTracker
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak writer] buffer, _ in
                guard let floats = writer?.process(buffer: buffer) else { return }
                Task { @MainActor in
                    tracker.ingest(floats)
                }
            }

            try engine.start()

            currentFileURL = fileURL
            recordedFileURL = nil
            elapsedTime = 0
            recordingStartedAt = Date()
            isRecording = true
            startTimer()
        } catch let appError as AppError {
            inputNode.removeTap(onBus: 0)
            tapWriter = nil
            currentFileURL = nil
            try? FileManager.default.removeItem(at: fileURL)
            throw appError
        } catch {
            inputNode.removeTap(onBus: 0)
            tapWriter = nil
            currentFileURL = nil
            try? FileManager.default.removeItem(at: fileURL)
            throw AppError.recordingFailed("Recording could not start.")
        }
    }

    func stopRecording() async throws -> URL {
        guard let fileURL = currentFileURL, tapWriter != nil else {
            throw AppError.recordingFailed("There is no active recording to stop.")
        }

        engine.inputNode.removeTap(onBus: 0)
        // Blocks until any in-flight write from the last tap callback has
        // finished. Deliberately not bound to a local `let writer` — that
        // would itself keep AudioTapWriter alive past the `tapWriter = nil`
        // below (same class of bug as the tap closure's capture), delaying
        // AVAudioFile's header-finalizing deinit past the file read that
        // follows.
        tapWriter?.drainAndClose()
        tapWriter = nil
        currentFileURL = nil
        isRecording = false
        stopTimer()
        // Deliberately don't stop the engine here: tearing it down would force
        // the next recording to pay the same hardware warm-up cost the
        // session-reuse fix eliminated. It's stopped in endSession() when the
        // recording screen is left.

        let wavFile = try PCM16WAVFile(contentsOf: fileURL)
        try wavFile.writeCanonical(to: fileURL)
        try validateRecordedFile(at: fileURL)
        recordedFileURL = fileURL
        return fileURL
    }

    func cancelRecording() {
        let fileURL = currentFileURL
        engine.inputNode.removeTap(onBus: 0)
        tapWriter?.drainAndClose()
        tapWriter = nil
        currentFileURL = nil
        isRecording = false
        elapsedTime = 0
        recordedFileURL = nil
        stopTimer()
        // See stopRecording(): keep the engine warm for the next attempt.

        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let recordingStartedAt else { return }
                elapsedTime = Date().timeIntervalSince(recordingStartedAt)
                if elapsedTime >= maxDuration {
                    elapsedTime = maxDuration
                    stopTimer()
                    maximumDurationReachedHandler?()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        recordingStartedAt = nil
    }

    private func validateRecordedFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppError.audioFileMissing
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        guard fileSize > 0 else {
            throw AppError.audioFileEmpty
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
