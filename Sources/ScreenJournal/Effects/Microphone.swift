import AppKit
import AVFoundation
import JournalCore
import os

/// A microphone, recorded into memory as 16 kHz mono: all the transcriber uses, and small to send.
/// Nothing is written to disk. Every step is logged (`log stream --predicate 'category == "microphone"'`), never the audio.
///
/// A capture session rather than an audio engine: it opens the microphone by id, follows a Bluetooth headset
/// into call mode on its own, and reports trouble as an error, where an engine aborts the app on a format it didn't expect.
final class Microphone: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    static let sampleRate = 16_000
    private static let log = Logger(subsystem: "com.filippofantozzi.ScreenJournal", category: "microphone")

    private var session: AVCaptureSession?
    private var failed: NSObjectProtocol?
    private let queue = DispatchQueue(label: "com.filippofantozzi.ScreenJournal.microphone")
    private let lock = NSLock()
    private var samples: [Int16] = []
    private var buffers = 0
    private var startedAt = Date()
    /// When the first sound arrived. Until then a Bluetooth headset is still switching into call mode
    /// and sends pure zeros.
    private var liveAt: Date?
    private var onLevel: @Sendable (Float) -> Void = { _ in }

    static var isAllowed: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    static var wasAsked: Bool { AVCaptureDevice.authorizationStatus(for: .audio) != .notDetermined }

    /// Shows the system prompt the first time; after that, only the Privacy pane can change the answer.
    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func openPrivacyPane() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    /// Records from the microphone with this Core Audio id, or the system's default input when nil.
    /// `onLevel` gets 0–1 loudness many times a second, off the main thread, from the moment sound arrives.
    func start(from id: String?, onLevel: @escaping @Sendable (Float) -> Void) -> Result<Void, LabelError> {
        Self.log.info("start: \(id ?? "default", privacy: .public)")
        guard let device = id.flatMap(AVCaptureDevice.init(uniqueID:)) ?? AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return failure("no device") }
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        let session = AVCaptureSession()
        guard session.canAddInput(input), session.canAddOutput(output) else { return failure("session refused \(device.localizedName)") }
        session.addInput(input)
        session.addOutput(output)
        lock.withLock {
            samples = []
            buffers = 0
            liveAt = nil
            startedAt = Date()
            self.onLevel = onLevel
        }
        failed = NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: nil) { note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            Self.log.error("runtime error: \(error?.localizedDescription ?? "unknown", privacy: .public)")
        }
        session.startRunning()
        self.session = session
        Self.log.info("running on \(device.localizedName, privacy: .public): \(session.isRunning)")
        return .success(())
    }

    /// What was recorded, as a WAV file, how long it lasts, and whether anything was heard at all.
    func stop() -> (wav: Data, seconds: TimeInterval, silent: Bool) {
        session?.stopRunning()
        session = nil
        if let failed { NotificationCenter.default.removeObserver(failed) }
        failed = nil
        // A buffer already in flight may still land; past this point it's dropped.
        let (recorded, buffers, wait) = lock.withLock {
            defer {
                samples = []
                onLevel = { _ in }
            }
            return (samples, self.buffers, liveAt.map { $0.timeIntervalSince(startedAt) })
        }
        let seconds = Double(recorded.count) / Double(Self.sampleRate)
        let peak = recorded.lazy.map { abs(Int32($0)) }.max() ?? 0
        Self.log.info("stop: \(buffers) buffers, \(seconds, format: .fixed(precision: 1)) s, peak \(peak), live after \(wait.map { "\(Int($0 * 1000)) ms" } ?? "never", privacy: .public)")
        return (WAV.encode(samples: recorded, sampleRate: Self.sampleRate), seconds, Silence.isSilent(recorded))
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(block)
        var chunk = [Int16](repeating: 0, count: length / 2)
        let copied = chunk.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
        guard copied == kCMBlockBufferNoErr else { return }
        let sounds = chunk.contains { $0 != 0 }
        let (count, onLevel, live) = lock.withLock {
            buffers += 1
            samples.append(contentsOf: chunk)
            if sounds, liveAt == nil { liveAt = Date() }
            return (buffers, self.onLevel, liveAt != nil)
        }
        if count == 1 { Self.log.info("first buffer: \(Self.describe(sampleBuffer), privacy: .public)") }
        if live { onLevel(Loudness.level(chunk)) }
    }

    private func failure(_ reason: String) -> Result<Void, LabelError> {
        Self.log.error("start failed: \(reason, privacy: .public)")
        return .failure(LabelError(message: "No microphone."))
    }

    /// The format actually delivered, to confirm it's the 16 kHz mono 16-bit asked for.
    private static func describe(_ buffer: CMSampleBuffer) -> String {
        guard let format = CMSampleBufferGetFormatDescription(buffer),
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        else { return "unknown format" }
        return "\(CMSampleBufferGetNumSamples(buffer)) frames, \(stream.mSampleRate) Hz, \(stream.mChannelsPerFrame) ch, \(stream.mBitsPerChannel) bit"
    }
}
