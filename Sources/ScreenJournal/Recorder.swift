import CoreGraphics
import Foundation
import JournalCore

/// The capture loop: every tick, decide whether to look, then keep only what changed.
@MainActor
final class Recorder {
    struct OpenFrame {
        var record: FrameRecord
        let signature: FrameSignature
    }

    enum TickOutcome {
        case captured(kept: Int)
        case skipped(SkipReason)
        case noScreenAccess
        case failed(Error)
    }

    private let store: JournalStore
    private let lock = LockWatcher()
    private var open: [Int: OpenFrame] = [:]
    private var lastText: [Int: (frameID: String, text: String)] = [:]
    private var lastGate: CaptureGate?

    init(store: JournalStore) {
        self.store = store
    }

    func tick(policy: CapturePolicy, isPaused: Bool) async -> TickOutcome {
        let now = Date()
        let frontmost = ActivityReader.frontmost
        let gate = policy.gate(CaptureConditions(
            isPaused: isPaused, isLocked: lock.isLocked,
            idleSeconds: ActivityReader.idleSeconds, frontmostBundleID: frontmost?.bundleIdentifier
        ))
        logTransition(to: gate, at: now, app: frontmost?.localizedName)

        if case .skip(let reason) = gate {
            closeAll(at: now)
            return .skipped(reason)
        }
        guard SystemAccess.hasScreenAccess else {
            closeAll(at: now)
            return .noScreenAccess
        }

        do {
            let shots = try await ScreenCapturer.captureAll(excludingBundleIDs: policy.excludedBundleIDs)
            let windows = ActivityReader.windows()
            let focusedBounds = windows.first { $0.bundleID == frontmost?.bundleIdentifier && $0.layer == 0 }?.bounds
            var kept = 0
            for shot in shots {
                let top = WindowPlacement.topWindow(on: shot.bounds, among: windows)
                let signature = FrameSignature(thumbnail: ImageCodec.thumbnail(of: shot.image), bundleID: top?.bundleID, windowTitle: top?.title)
                switch policy.decide(current: signature, previous: open[shot.index]?.signature) {
                case .unchanged:
                    open[shot.index]?.record.end = now
                case .keep:
                    close(display: shot.index, at: now)
                    let focused = focusedBounds.map { shot.bounds.contains(CGPoint(x: $0.midX, y: $0.midY)) } ?? (shot.index == 1)
                    try await keep(shot, top: top, focused: focused, signature: signature, at: now)
                    kept += 1
                }
            }
            return .captured(kept: kept)
        } catch {
            closeAll(at: now)
            return .failed(error)
        }
    }

    func record(_ event: EventRecord) {
        try? store.append(event)
    }

    /// Writes every open frame; call before quitting or when capture stops.
    func closeAll(at date: Date) {
        for display in open.keys { close(display: display, at: date) }
    }

    private func keep(_ shot: DisplayShot, top: WindowInfo?, focused: Bool, signature: FrameSignature, at now: Date) async throws {
        let id = DayStamp(now, in: store.timeZone).frameID(display: shot.index)
        let image = try store.writeImage(shot.image, id: id, at: now)
        let text = await TextRecognizer.text(in: shot.image)
        let previous = lastText[shot.index]
        let repeated = previous?.text == text
        if !repeated { lastText[shot.index] = (id, text) }

        open[shot.index] = OpenFrame(
            record: FrameRecord(
                id: id, start: now, end: now, display: shot.index, focused: focused,
                app: top?.app, bundleID: top?.bundleID, windowTitle: top?.title, image: image,
                text: repeated || text.isEmpty ? nil : text, textSameAs: repeated ? previous?.frameID : nil
            ),
            signature: signature
        )
    }

    private func close(display: Int, at date: Date) {
        guard var frame = open.removeValue(forKey: display) else { return }
        frame.record.end = max(frame.record.end, date)
        try? store.append(frame.record)
    }

    private func logTransition(to gate: CaptureGate, at date: Date, app: String?) {
        defer { lastGate = gate }
        guard gate != lastGate, lastGate != nil || gate != .capture else { return }
        switch gate {
        case .capture: record(EventRecord(at: date, kind: .active))
        case .skip(let reason): record(EventRecord(at: date, kind: reason.eventKind, app: reason == .excludedApp ? nil : app))
        }
    }
}
