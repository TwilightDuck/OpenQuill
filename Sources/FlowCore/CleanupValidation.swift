import Foundation

public enum CleanupValidation {
    /// Generation is optional. Reject empty, truncated or expanded output and changed
    /// literal numbers/phrases; this is not a guarantee of semantic equivalence.
    public static func accepts(_ output: String, original: String, protectedPhrases: [String]) -> Bool {
        let count = original.count
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              output.count <= max(count + 8, count * 2), output.count >= count / 3 else { return false }
        let numbers = try! NSRegularExpression(pattern: "[0-9]+(?:[.,:/-][0-9]+)*")
        func values(_ text: String) -> [String] {
            numbers.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }
        }
        guard values(output) == values(original) else { return false }
        for phrase in protectedPhrases where !phrase.isEmpty {
            let regex = try! NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: phrase), options: .caseInsensitive)
            if regex.numberOfMatches(in: output, range: NSRange(output.startIndex..., in: output)) < regex.numberOfMatches(in: original, range: NSRange(original.startIndex..., in: original)) { return false }
        }
        return true
    }
}
