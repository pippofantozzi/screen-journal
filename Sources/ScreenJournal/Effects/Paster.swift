import AppKit

/// Types text where her cursor is by pasting it, then gives the clipboard back.
@MainActor
enum Paster {
    enum Outcome { case pasted, copied }

    /// Where nothing takes typing, the text stays on the clipboard for her to paste.
    static func paste(_ text: String) async -> Outcome {
        guard let element = WindowContext.focusedElement(), WindowContext.takesText(element) else {
            Clipboard.write(text, transient: false)
            return .copied
        }
        let saved = Clipboard.snapshot()
        let ours = Clipboard.write(text, transient: true)
        Keystroke.command(Keystroke.paste)
        // The app reads the clipboard when it handles ⌘V, a moment later.
        try? await Task.sleep(for: .milliseconds(500))
        if Clipboard.board.changeCount == ours { Clipboard.restore(saved) }
        return .pasted
    }
}
