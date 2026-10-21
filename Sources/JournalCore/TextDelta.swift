import Foundation

public enum TextDelta {
    /// Trimmed, non-empty lines of `current` not in `seen`, first occurrence only.
    public static func newLines(_ current: String, seen: Set<String>) -> [String] {
        var seen = seen
        return lines(current).filter { seen.insert($0).inserted }
    }

    /// The trimmed, non-empty lines of `text`, as `newLines` compares them.
    public static func lineSet(_ text: String) -> Set<String> {
        Set(lines(text))
    }

    private static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
