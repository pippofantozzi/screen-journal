import AppKit
import Foundation
import JournalCore

/// The capture loop: every tick, decide whether to look, then keep only what changed.
@MainActor
final class Recorder {
    /// What was last recorded on one display, so the next record only adds what's new.
    struct DisplayMemory {
        var signature: FrameSignature
        /// Lines already on record during this visit to the window.
        var seen: Set<String>
        var day: String
        var image: String
        var imageAt: Date
    }

    enum TickOutcome {
        case captured(kept: Int)
        case skipped(SkipReason)
        case noScreenAccess
        case failed(Error)
    }

    private let store: JournalStore
    private let lock = LockWatcher()
    private let ownBundleID = Bundle.main.bundleIdentifier
    private var open: [Int: FrameRecord] = [:]
    private var memory: [Int: DisplayMemory] = [:]
    private var lastGate: CaptureGate?

    init(store: JournalStore) {
        self.store = store
    }

    /// The open record on the display holding the frontmost app.
    var focusedFrame: FrameRecord? { open.values.first(where: \.focused) }

    func tick(policy: CapturePolicy, isPaused: Bool) async -> TickOutcome {
        let now = Date()
        let frontmost = ActivityReader.frontmost
        let windows = ActivityReader.windows()
        let frontWindow = windows.first { $0.bundleID == frontmost?.bundleIdentifier && $0.layer == 0 }
        let gate = policy.gate(CaptureConditions(
            isPaused: isPaused, isLocked: lock.isLocked, idleSeconds: ActivityReader.idleSeconds,
            frontmostBundleID: frontmost?.bundleIdentifier, frontmostWindowTitle: frontWindow?.title
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
            for gone in Set(open.keys).subtracting(shots.map(\.index)) { close(display: gone, at: now) }
            let focusedDisplay = frontWindow.flatMap { w in
                shots.first { $0.bounds.contains(CGPoint(x: w.bounds.midX, y: w.bounds.midY)) }?.index
            } ?? 1
            var kept = 0
            for shot in shots {
                let focused = shot.index == focusedDisplay
                let top = WindowPlacement.topWindow(
                    on: shot.bounds, among: windows,
                    preferring: focused ? frontmost?.bundleIdentifier : nil, ownBundleID: ownBundleID
                ) ?? (focused ? windowless(frontmost, on: shot.bounds) : nil)
                let signature = FrameSignature(thumbnail: ImageCodec.thumbnail(of: shot.image), bundleID: top?.bundleID, windowTitle: top?.title)
                let previous = memory[shot.index]
                switch policy.decide(current: signature, previous: previous?.signature, lastImageAt: previous?.imageAt, now: now) {
                case .unchanged:
                    open[shot.index]?.end = now
                case .record(let saveImage):
                    try await record(shot, top: top, focused: focused, signature: signature, saveImage: saveImage, at: now)
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

    /// Writes every open frame and forgets each display's history, so the next frame after a gap is a full record.
    /// Call before quitting or when capture stops.
    func closeAll(at date: Date) {
        for display in open.keys { close(display: display, at: date) }
        memory.removeAll()
    }

    private func record(
        _ shot: DisplayShot, top: WindowInfo?, focused: Bool, signature: FrameSignature, saveImage: Bool, at now: Date
    ) async throws {
        close(display: shot.index, at: now)
        let id = DayStamp(now, in: store.timeZone).frameID(display: shot.index)
        let previous = memory[shot.index]
        // Image paths are relative to the day folder, so a new day always gets its own image.
        let shared = previous.flatMap { !saveImage && store.day(of: $0.imageAt) == store.day(of: now) ? $0 : nil }
        let image = try shared?.image ?? store.writeImage(shot.image, id: id, at: now)

        let ocr = await TextRecognizer.text(in: shot.image)
        let day = store.day(of: now)
        // Same window, same day, and something already on record: continue the visit.
        let visit = previous.flatMap {
            !$0.seen.isEmpty && $0.day == day
                && $0.signature.bundleID == signature.bundleID && $0.signature.windowTitle == signature.windowTitle ? $0 : nil
        }
        let newLines = visit.map { TextDelta.newLines(ocr, seen: $0.seen) } ?? []
        let seen = visit.map { $0.seen.union(newLines) } ?? TextDelta.lineSet(ocr)

        memory[shot.index] = DisplayMemory(signature: signature, seen: seen, day: day, image: image, imageAt: shared?.imageAt ?? now)
        open[shot.index] = FrameRecord(
            id: id, start: now, end: now, display: shot.index, focused: focused,
            app: top?.app, bundleID: top?.bundleID, windowTitle: top?.title, image: image,
            text: visit == nil && !ocr.isEmpty ? ocr : nil, newLines: newLines.isEmpty ? nil : newLines
        )
    }

    /// The frontmost app when it has no window here, e.g. Finder showing just the desktop.
    private func windowless(_ app: NSRunningApplication?, on bounds: CGRect) -> WindowInfo? {
        guard let name = app?.localizedName,
              !SystemApps.isIgnored(app: name, bundleID: app?.bundleIdentifier, ownBundleID: ownBundleID)
        else { return nil }
        return WindowInfo(app: name, bundleID: app?.bundleIdentifier, title: nil, bounds: bounds, layer: 0)
    }

    private func close(display: Int, at date: Date) {
        guard var frame = open.removeValue(forKey: display) else { return }
        frame.end = max(frame.end, date)
        try? store.append(frame)
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
