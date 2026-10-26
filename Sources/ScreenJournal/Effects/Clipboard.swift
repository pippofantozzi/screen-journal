import AppKit

/// The general pasteboard, borrowed for a moment and given back as it was.
@MainActor
enum Clipboard {
    typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    /// Clipboard managers skip items marked this way, so dictated text doesn't pile up in their history.
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    static var board: NSPasteboard { .general }

    static func snapshot() -> Snapshot {
        (board.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    static func restore(_ snapshot: Snapshot) {
        board.clearContents()
        board.writeObjects(snapshot.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        })
    }

    /// Returns the change count it left, to tell later whether anyone copied since.
    @discardableResult
    static func write(_ text: String, transient isTransient: Bool) -> Int {
        board.clearContents()
        board.setString(text, forType: .string)
        if isTransient { board.setData(Data(), forType: transient) }
        return board.changeCount
    }
}

/// A ⌘-shortcut sent to the frontmost app, as if typed. Needs the Accessibility grant.
enum Keystroke {
    static let copy = CGKeyCode(8)   // C
    static let paste = CGKeyCode(9)  // V

    static func command(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
