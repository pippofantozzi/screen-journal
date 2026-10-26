import AppKit
import SwiftUI

/// A dark capsule at the bottom of the screen. Connecting: dim dots, lit one after another, until the microphone
/// sends sound. Listening: bars (after a pencil when editing) mirrored from the center, the newest sound in the middle,
/// with a glow that swells with her voice.
/// Writing: a slow wave through the same bars. Something off: one line.
struct DictationPill: View {
    let controller: DictationController

    static let barWidth: CGFloat = 3
    static let tallest: CGFloat = 24
    static let shortest: CGFloat = 3

    var body: some View {
        HStack(spacing: 10) {
            switch controller.phase {
            case .listening:
                if controller.isEditing { Image(systemName: "pencil").font(.callout.weight(.semibold)) }
                if controller.isConnecting {
                    TimelineView(.animation) { context in connecting(at: context.date.timeIntervalSinceReferenceDate) }
                } else {
                    bars(mirrored(controller.levels))
                }
            case .working:
                TimelineView(.animation) { context in
                    bars(wave(at: context.date.timeIntervalSinceReferenceDate)).opacity(0.75)
                }
            case .notice(let message):
                Text(message).font(.callout)
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Capsule().fill(.black.opacity(0.88)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .accentColor.opacity(Double(glow)), radius: 6 + CGFloat(glow) * 14)
        .foregroundStyle(.white)
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: controller.levels)
    }

    /// Only while listening, and only as loud as the last moment.
    private var glow: Float {
        guard controller.phase == .listening else { return 0 }
        return 0.15 + 0.6 * (controller.levels.suffix(3).max() ?? 0)
    }

    /// Oldest at both edges, newest in the middle, so each word pulses outward.
    private func mirrored(_ levels: [Float]) -> [Float] {
        levels + Array(levels.reversed().dropFirst())
    }

    /// A crest travelling left to right while the text is written.
    private func wave(at time: TimeInterval) -> [Float] {
        let count = controller.levels.count * 2 - 1
        return (0..<count).map { i -> Float in
            let phase: Double = time * 6 - Double(i) * 0.55
            return Float(0.15 + 0.175 * (1 + sin(phase)))
        }
    }

    /// Resting bars with a light running across them: on, not yet hearing.
    private func connecting(at time: TimeInterval) -> some View {
        let count = controller.levels.count * 2 - 1
        return HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<count, id: \.self) { i in
                let phase: Double = time * 5 - Double(i) * 0.45
                Capsule()
                    .frame(width: Self.barWidth, height: Self.shortest)
                    .opacity(0.25 + 0.6 * max(0, sin(phase)))
            }
        }
        .frame(height: Self.tallest)
    }

    private func bars(_ levels: [Float]) -> some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                Capsule().frame(width: Self.barWidth, height: height(level, at: index, of: levels.count))
            }
        }
        .frame(height: Self.tallest)
    }

    /// Bars near the edges reach less high, so the shape reads as one wave.
    private func height(_ level: Float, at index: Int, of count: Int) -> CGFloat {
        let middle = CGFloat(count - 1) / 2
        let fromCenter: CGFloat = abs(CGFloat(index) - middle) / (middle + 1)
        let taper: CGFloat = 1 - 0.45 * fromCenter * fromCenter
        return Self.shortest + CGFloat(level) * (Self.tallest - Self.shortest) * taper
    }
}

/// Floats over every app without taking focus or clicks, so the text lands where her cursor was.
@MainActor
final class DictationPillPanel {
    /// Room around the capsule for its glow.
    private static let size = CGSize(width: 300, height: 80)
    private let panel: NSPanel

    init(controller: DictationController) {
        panel = NSPanel(contentRect: CGRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: DictationPill(controller: controller))
    }

    /// On the screen she's working on, just above the Dock.
    func show() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 8))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}
