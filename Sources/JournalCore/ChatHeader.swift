import Foundation

/// One line of recognized text and where it sits, as fractions of the image with `top` measured down from the top edge.
public struct TextLine: Equatable, Sendable {
    public let text: String
    public let minX: Double
    public let maxX: Double
    public let top: Double
    public let height: Double

    public init(text: String, minX: Double, maxX: Double, top: Double, height: Double) {
        self.text = text
        self.minX = minX
        self.maxX = maxX
        self.top = top
        self.height = height
    }
}

/// Chat apps title every window with the app's name; who the chat is with is only in the conversation's header.
public enum ChatHeader {
    /// "Forgia LFG! — WhatsApp": WhatsApp's header line sits level with the "WhatsApp" heading, right of the chat list.
    /// Other titles, and a WhatsApp window with no chat open, come back unchanged.
    public static func title(_ windowTitle: String?, lines: [TextLine]) -> String? {
        guard windowTitle == "WhatsApp",
              let heading = lines.filter({ $0.text == "WhatsApp" }).max(by: { $0.height < $1.height })
        else { return windowTitle }
        let header = lines
            .filter { abs($0.top - heading.top) < 0.02 && $0.minX > heading.maxX + 0.05 && $0.minX < heading.minX + 0.4 }
            .filter { $0.text.filter(\.isLetter).count >= 2 }
            .min { $0.minX < $1.minX }
        return header.map { "\(Secrets.redact($0.text)) — WhatsApp" } ?? windowTitle
    }
}

/// Where a window is: the folder or file it shows, or the page's address.
public enum Place {
    public static func from(document: String?, pageURL: String?, addressBar: String?, home: String) -> String? {
        if let document, let url = URL(string: document), url.isFileURL {
            let path = url.path(percentEncoded: false)
            let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
            return trimmed.hasPrefix(home) ? "~" + trimmed.dropFirst(home.count) : trimmed
        }
        if let pageURL, !pageURL.isEmpty { return Secrets.redact(pageURL) }
        guard let shown = addressBar?.split(separator: " ").first.map(String.init),
              shown.contains("."), !shown.contains("…")
        else { return nil }
        return Secrets.redact(shown)
    }
}
