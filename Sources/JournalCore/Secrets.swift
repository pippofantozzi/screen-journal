import Foundation

/// Keys, tokens, payment cards, CPFs and OTP codes are blanked in screen text before it is written,
/// so the journal never holds a live credential and screenshots with them stay on the Mac.
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

    private static let bearerRegex = try! NSRegularExpression(
        pattern: #"\b(Bearer\s+)[A-Za-z0-9._~+/=-]{20,}"#,
        options: [.caseInsensitive]
    )

    /// Labeled verification / 2FA codes in English and Portuguese; only the code digits are replaced.
    private static let otpRegex = try! NSRegularExpression(
        pattern: #"(?i)((?:verification|security|login|one[- ]time|2fa|otp|auth(?:entication)?|c[oó]digo(?:\s+de\s+(?:verifica[çc][ãa]o|seguran[çc]a|acesso))?)(?:\s+(?:code|pin|number))?(?:\s*(?:is|é|:|-))?\s+)(\b\d{4,8}\b)"#
    )

    /// Formatted Brazilian CPF (###.###.###-##); validated with its mod-11 check digits before redacting.
    private static let cpfRegex = try! NSRegularExpression(pattern: #"\b\d{3}\.\d{3}\.\d{3}-\d{2}\b"#)

    /// Candidate payment card numbers (13–19 digits, optionally grouped by spaces or hyphens); Luhn-validated before redacting.
    private static let cardRegex = try! NSRegularExpression(pattern: #"(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)"#)

    public static func redact(_ text: String) -> String {
        var result = patterns.reduce(text) { $0.replacingOccurrences(of: $1, with: placeholder, options: .regularExpression) }
        result = replace(result, regex: bearerRegex) { match, ns in
            ns.substring(with: match.range(at: 1)) + placeholder
        }
        result = replace(result, regex: otpRegex) { match, ns in
            ns.substring(with: match.range(at: 1)) + placeholder
        }
        result = replace(result, regex: cpfRegex) { match, ns in
            let candidate = ns.substring(with: match.range)
            return isValidCPF(candidate) ? placeholder : nil
        }
        result = replace(result, regex: cardRegex) { match, ns in
            let candidate = ns.substring(with: match.range)
            return isValidCardNumber(candidate) ? placeholder : nil
        }
        return result
    }

    private static func replace(_ text: String, regex: NSRegularExpression, transform: (NSTextCheckingResult, NSString) -> String?) -> String {
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            if let replacement = transform(match, ns) {
                mutable.replaceCharacters(in: match.range, with: replacement)
            }
        }
        return mutable as String
    }

    /// Standard Luhn check for 13–19 digit payment cards. Rejects trivial all-same-digit runs and hyphenated dates/UUIDs.
    static func isValidCardNumber(_ candidate: String) -> Bool {
        let digits = candidate.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count), Set(digits).count > 1 else { return false }
        // Require either ungrouped digits or standard 4-digit/Amex card groupings to avoid matching phone numbers or dashed IDs.
        let separators = candidate.filter { $0 == " " || $0 == "-" }
        if !separators.isEmpty {
            let parts = candidate.split { $0 == " " || $0 == "-" }
            let sizes = parts.map(\.count)
            let standard = sizes == [4, 4, 4, 4] || sizes == [4, 6, 5] || sizes == [4, 4, 4, 4, 3] || sizes == [4, 4, 4, 1]
            guard standard else { return false }
        }
        var sum = 0
        for (i, d) in digits.reversed().enumerated() {
            if i % 2 == 1 {
                let doubled = d * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += d
            }
        }
        return sum % 10 == 0
    }

    /// Brazilian CPF check digits (mod 11).
    static func isValidCPF(_ candidate: String) -> Bool {
        let digits = candidate.compactMap(\.wholeNumberValue)
        guard digits.count == 11, Set(digits).count > 1 else { return false }
        func checkDigit(count: Int) -> Int {
            let sum = (0..<count).reduce(0) { $0 + digits[$1] * (count + 1 - $1) }
            let mod = (sum * 10) % 11
            return mod == 10 ? 0 : mod
        }
        return digits[9] == checkDigit(count: 9) && digits[10] == checkDigit(count: 10)
    }
}
