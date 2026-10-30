import AppKit
import ApplicationServices

/// The chat open in the WhatsApp Mac app, read from its header button through Accessibility.
/// nil without the grant, when WhatsApp isn't running, or when no chat is open.
enum WhatsAppWindow {
    static let bundleID = "net.whatsapp.WhatsApp"
    /// The header's stable identifier; its title is the chat's name exactly as the chat list shows it.
    private static let header = "NavigationBar_HeaderViewButton"

    static func openChatName() -> String? {
        guard WindowContext.isTrusted,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { return nil }
        let whatsapp = AXUIElementCreateApplication(app.processIdentifier)
        let windows = value(whatsapp, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let window = (value(whatsapp, kAXFocusedWindowAttribute) as! AXUIElement?) ?? windows.first
        guard let window else { return nil }
        var queue = [window], visited = 0
        while !queue.isEmpty, visited < 400 {
            let element = queue.removeFirst()
            visited += 1
            if value(element, kAXIdentifierAttribute) as? String == header {
                return (value(element, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
            }
            queue += value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        return nil
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var result: AnyObject?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }
}
