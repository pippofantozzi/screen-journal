import AppKit
import ApplicationServices
import JournalCore

/// What the Accessibility API says about an app's focused window. Needs the Accessibility grant.
enum WindowContext {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Adds the app to the Accessibility list (first call shows the system prompt), then opens the pane.
    static func requestTrust() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// One element of the focused window, flattened: enough to find a page address or a chat header.
    struct Element {
        let depth: Int
        let role: String
        let text: String
        let url: String?
        let frame: CGRect
    }

    /// The focused window's folder, file or page; nil without the grant or when the app says nothing.
    static func place(of pid: pid_t) -> String? {
        guard isTrusted, let window = focusedWindow(of: pid) else { return nil }
        if let document = document(of: window) {
            return Place.from(document: document, pageURL: nil, addressBar: nil, home: NSHomeDirectory())
        }
        let elements = elements(of: window, limit: 400, maxDepth: 12)
        let toolbarBottom = frame(of: window).minY + 160
        let page = elements.first { $0.role == "AXWebArea" && $0.url != nil }?.url
        let addressBar = elements.first { ["AXComboBox", "AXTextField"].contains($0.role) && $0.frame.minY < toolbarBottom && !$0.text.isEmpty }?.text
        return Place.from(document: nil, pageURL: page, addressBar: addressBar, home: NSHomeDirectory())
    }

    static func focusedWindow(of pid: pid_t) -> AXUIElement? {
        value(accessibleApp(pid), kAXFocusedWindowAttribute) as! AXUIElement?
    }

    /// The element that takes typing in the frontmost app, e.g. a text field; nil without the grant.
    static func focusedElement() -> AXUIElement? {
        guard isTrusted, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        return value(accessibleApp(pid), kAXFocusedUIElementAttribute) as! AXUIElement?
    }

    /// Its highlighted text: "" when nothing is highlighted, nil when the app doesn't say.
    static func selectedText(of element: AXUIElement) -> String? {
        value(element, kAXSelectedTextAttribute) as? String
    }

    private static func accessibleApp(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        // Chromium and Electron build their tree only for a client that asks; Firefox-based browsers wait for a screen reader.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        return app
    }

    /// The window's document (a file or folder, e.g. a terminal's working directory), as a URL string.
    static func document(of window: AXUIElement) -> String? {
        value(window, kAXDocumentAttribute) as? String
    }

    static func frame(of element: AXUIElement) -> CGRect {
        var origin = CGPoint.zero, size = CGSize.zero
        if let v = value(element, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &origin) }
        if let v = value(element, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &size) }
        return CGRect(origin: origin, size: size)
    }

    /// Breadth-first, at most `limit` elements, so a huge page can't stall a tick.
    static func elements(of window: AXUIElement, limit: Int, maxDepth: Int = 30) -> [Element] {
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var found: [Element] = []
        while !queue.isEmpty && found.count < limit {
            let (element, depth) = queue.removeFirst()
            let texts = [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute].compactMap { value(element, $0) as? String }
            let rawURL = value(element, kAXURLAttribute)
            let url = (rawURL as? URL)?.absoluteString ?? rawURL as? String
            found.append(Element(
                depth: depth, role: value(element, kAXRoleAttribute) as? String ?? "?",
                text: texts.filter { !$0.isEmpty }.joined(separator: " · "), url: url, frame: frame(of: element)
            ))
            guard depth < maxDepth else { continue }
            for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] { queue.append((child, depth + 1)) }
        }
        return found
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var result: AnyObject?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }
}
