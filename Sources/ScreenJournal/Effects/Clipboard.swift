import AppKit

/// The general pasteboard, borrowed for a moment and given back as it was.
@MainActor
enum Clipboard {
    typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

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

    static func write(_ text: String) {
        board.clearContents()
        board.setString(text, forType: .string)
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
