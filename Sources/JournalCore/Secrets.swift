import Foundation

/// Keys and tokens are blanked in screen text before it is written, so the journal never holds a live credential.
public enum Secrets {
    public static let placeholder = "[redacted]"

    /// Known key formats only: order numbers, commit hashes and record IDs are what automations match on, so they stay.
    private static let patterns = [
        #"\b(?:sk|pk|rk)[-_][A-Za-z0-9_-]{20,}"#,
        #"\b(?:vck|ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]{16,}"#,
        #"\bxox[abprs]-[A-Za-z0-9-]{10,}"#,
        #"\bAKIA[0-9A-Z]{16}\b"#,
        #"\bAIza[0-9A-Za-z_-]{30,}"#,
        #"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#,
    ]

    public static func redact(_ text: String) -> String {
        patterns.reduce(text) { $0.replacingOccurrences(of: $1, with: placeholder, options: .regularExpression) }
    }
}
