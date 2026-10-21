/// Window titles as a stable name for "the same window".
public enum WindowTitle {
    /// Drops leading status glyphs (spinners like ◐ ⠙ ✳, unsaved dots like ●) that apps animate in the title,
    /// so a terminal busy with a task stays one window. Nil when nothing else is left.
    public static func stable(_ title: String?) -> String? {
        guard let title else { return nil }
        let rest = title.unicodeScalars.drop { scalar in
            scalar.properties.isWhitespace || [.otherSymbol, .nonspacingMark].contains(scalar.properties.generalCategory)
        }
        return rest.isEmpty ? nil : String(String.UnicodeScalarView(rest))
    }
}
