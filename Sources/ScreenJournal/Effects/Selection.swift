import AppKit

/// The text highlighted in the frontmost app when a dictation starts.
@MainActor
enum Selection {
    /// Asks Accessibility first; apps that don't answer (some Electron and web views) are asked with ⌘C,
    /// and the clipboard is put back. Nil when nothing is highlighted.
    static func read() async -> String? {
        let element = WindowContext.focusedElement()
        if let element, let text = WindowContext.selectedText(of: element) { return text.isEmpty ? nil : text }
        return await copied()
    }

    private static func copied() async -> String? {
        let saved = Clipboard.snapshot()
        let before = Clipboard.board.changeCount
        Keystroke.command(Keystroke.copy)
        for _ in 0..<10 where Clipboard.board.changeCount == before {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard Clipboard.board.changeCount != before else { return nil }
        let text = Clipboard.board.string(forType: .string)
        Clipboard.restore(saved)
        return text
    }
}
