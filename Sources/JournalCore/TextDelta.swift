import Foundation

public enum TextDelta {
    /// Trimmed, non-empty lines of `current` that aren't in `previous`, first occurrence only.
    public static func newLines(_ current: String, since previous: String) -> [String] {
        var seen = Set(lines(previous))
        return lines(current).filter { seen.insert($0).inserted }
    }

    private static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
