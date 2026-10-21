/// Window titles as a stable name for "the same window".
public enum WindowTitle {
    /// Drops what apps animate in the title, so one window keeps one name:
    /// leading status glyphs (spinners like ◐ ⠙ ✳, unsaved dots like ●) and unread counters like "(3) " or " (12)".
    /// Nil when nothing else is left.
    public static func stable(_ title: String?) -> String? {
        guard let title, let name = withoutGlyphs(title) else { return nil }
        return withoutCounters(name)
    }

    private static func withoutGlyphs(_ title: String) -> String? {
        let rest = title.unicodeScalars.drop { scalar in
            scalar.properties.isWhitespace || [.otherSymbol, .nonspacingMark].contains(scalar.properties.generalCategory)
        }
        return rest.isEmpty ? nil : String(String.UnicodeScalarView(rest))
    }

    /// Keeps a title that is nothing but a counter.
    private static func withoutCounters(_ title: String) -> String {
        let name = title
            .replacing(/^\(\d+\+?\)\s+/, with: "")
            .replacing(/\s+\(\d+\)$/, with: "")
        return name.isEmpty ? title : name
    }
}
