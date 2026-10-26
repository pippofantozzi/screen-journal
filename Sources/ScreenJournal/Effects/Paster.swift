import AppKit

/// Types text where her cursor is by pasting it. The text stays on the clipboard afterwards,
/// so where the paste didn't land she can press ⌘V herself.
@MainActor
enum Paster {
    /// Always sends ⌘V: web apps such as WhatsApp Web take typing without saying so through Accessibility.
    static func paste(_ text: String) {
        Clipboard.write(text)
        Keystroke.command(Keystroke.paste)
    }
}
