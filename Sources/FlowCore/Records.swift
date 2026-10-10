import Foundation

public struct Dictation: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let original: String
    public var text: String
    public var corrected: String?
    public let appName: String
    public let bundleID: String
    public let language: String
    public let audioSeconds: Double
    public let processingSeconds: Double
    public var delivery: String
    public var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }

    public init(id: UUID = UUID(), date: Date = Date(), original: String, text: String,
                appName: String, bundleID: String, language: String, audioSeconds: Double,
                processingSeconds: Double, delivery: String) {
        self.id = id; self.date = date; self.original = original; self.text = text
        self.appName = appName; self.bundleID = bundleID; self.language = language
        self.audioSeconds = audioSeconds; self.processingSeconds = processingSeconds
        self.delivery = delivery
    }
}

public struct Correction: Codable, Identifiable, Sendable {
    public var id = UUID()
    public let from: String
    public let to: String
    public let bundleID: String
    public let language: String
    public var observations: Int
    public var enabled: Bool
    public var userDisabled: Bool? = nil
    public init(from: String, to: String, bundleID: String, language: String, observations: Int = 1, enabled: Bool = false) {
        self.from = from; self.to = to; self.bundleID = bundleID; self.language = language
        self.observations = observations; self.enabled = enabled
    }
}

public struct FlowData: Codable, Sendable {
    public var dictations: [Dictation] = []
    public var corrections: [Correction] = []
    public init() {}

    @discardableResult public mutating func teach(from: String, to: String, bundleID: String = "*", language: String = "*") -> Bool {
        let from = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty, from != to, from.count <= 128, to.count <= 128,
              from.contains(where: \.isLetter), to.contains(where: \.isLetter),
              !from.contains("\n"), !to.contains("\n") else { return false }
        corrections.removeAll { $0.from.caseInsensitiveCompare(from) == .orderedSame && $0.bundleID == bundleID && $0.language == language }
        corrections.append(Correction(from: from, to: to, bundleID: bundleID, language: language, observations: 0, enabled: true))
        return true
    }

    public mutating func learn(original: String, edited: String, bundleID: String, language: String) {
        guard let change = TextProcessing.correction(original: original, edited: edited) else { return }
        // Conflicting corrections stay inactive until the user chooses one.
        let conflict = corrections.contains { $0.from.caseInsensitiveCompare(change.from) == .orderedSame && $0.to != change.to && $0.bundleID == bundleID && $0.language == language }
        if conflict {
            for index in corrections.indices where corrections[index].from.caseInsensitiveCompare(change.from) == .orderedSame && corrections[index].bundleID == bundleID && corrections[index].language == language {
                corrections[index].enabled = false
            }
        }
        if let index = corrections.firstIndex(where: { $0.from.caseInsensitiveCompare(change.from) == .orderedSame && $0.to == change.to && $0.bundleID == bundleID && $0.language == language }) {
            corrections[index].observations += 1
            if corrections[index].observations >= 2 && !conflict && corrections[index].userDisabled != true { corrections[index].enabled = true }
        } else {
            corrections.append(Correction(from: change.from, to: change.to, bundleID: bundleID, language: language))
        }
    }
}

public enum TextProcessing {
    /// A readable editor may expose text but omit its caret. Confirm the complete
    /// insertion without guessing that caret or accepting a partial text change.
    public static func isExactInsertion(before: String, after: String, inserted: String) -> Bool {
        let afterCount = after.utf16.count
        let beforeCount = before.utf16.count
        guard !inserted.isEmpty, afterCount >= beforeCount, afterCount - beforeCount == inserted.utf16.count else { return false }
        let value = after as NSString
        var search = NSRange(location: 0, length: value.length)
        // ponytail: cap repeated-text candidates; ambiguous fields safely skip Enter.
        for _ in 0..<100 {
            let match = value.range(of: inserted, options: .literal, range: search)
            guard match.location != NSNotFound else { return false }
            if value.replacingCharacters(in: match, with: "") == before { return true }
            let next = match.location + 1
            search = NSRange(location: next, length: value.length - next)
        }
        return false
    }

    public static func clean(_ raw: String, corrections: [Correction], bundleID: String, language: String, spokenPunctuation: Bool) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if spokenPunctuation {
            let commands = language == "nl"
                ? [("nieuwe alinea", "\n\n"), ("nieuwe regel", "\n"), ("vraagteken", "?"), ("uitroepteken", "!"), ("puntkomma", ";"), ("dubbele punt", ":"), ("komma", ",")]
                : [("new paragraph", "\n\n"), ("new line", "\n"), ("question mark", "?"), ("exclamation mark", "!"), ("semicolon", ";"), ("full stop", "."), ("comma", ",")]
            for (command, replacement) in commands { text = replacePhrase(command, with: replacement, in: text) }
            text = text.replacingOccurrences(of: "[ \\t]+([,.;:?!])", with: "$1", options: .regularExpression)
            text = text.replacingOccurrences(of: "[ \\t]*\\n[ \\t]*", with: "\n", options: .regularExpression)
        }
        // Match the original string once so replacements never cascade into another rule.
        let rules = corrections.filter { $0.enabled && ($0.bundleID == bundleID || $0.bundleID == "*") && ($0.language == language || $0.language == "*") }
            .sorted {
                if $0.from.count != $1.from.count { return $0.from.count > $1.from.count }
                // An explicit spelling choice wins over an older automatic guess.
                if ($0.observations == 0) != ($1.observations == 0) { return $0.observations == 0 }
                let first = ($0.bundleID == bundleID ? 2 : 0) + ($0.language == language ? 1 : 0)
                let second = ($1.bundleID == bundleID ? 2 : 0) + ($1.language == language ? 1 : 0)
                return first > second
            }
        if !rules.isEmpty {
            let alternatives = rules.map { NSRegularExpression.escapedPattern(for: $0.from) }.joined(separator: "|")
            let pattern = "(?<![\\p{L}\\p{N}_])(?:" + alternatives + ")(?![\\p{L}\\p{N}_])"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                    let phrase = (text as NSString).substring(with: match.range)
                    if let rule = rules.first(where: { $0.from.caseInsensitiveCompare(phrase) == .orderedSame }) {
                        text = (text as NSString).replacingCharacters(in: match.range, with: rule.to)
                    }
                }
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacePhrase(_ phrase: String, with replacement: String, in text: String) -> String {
        let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![\\p{L}\\p{N}_])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }

    public static func correction(original: String, edited: String, requireSharedContext: Bool = false) -> (from: String, to: String)? {
        let before = original.split(whereSeparator: \.isWhitespace).map(String.init)
        let after = edited.split(whereSeparator: \.isWhitespace).map(String.init)
        guard before != after, !before.isEmpty, !after.isEmpty else { return nil }
        var start = 0
        while start < min(before.count, after.count) && before[start] == after[start] { start += 1 }
        var end = 0
        while end < min(before.count, after.count) - start && before[before.count - 1 - end] == after[after.count - 1 - end] { end += 1 }
        guard !requireSharedContext || start > 0 || end > 0 else { return nil }
        let from = before[start..<(before.count - end)].joined(separator: " ")
        let to = after[start..<(after.count - end)].joined(separator: " ")
        // ponytail: learn only short contiguous substitutions; complex rewrites need explicit vocabulary.
        guard !from.isEmpty, !to.isEmpty, from.count <= 64, to.count <= 64,
              before.count - start - end <= 3, after.count - start - end <= 3,
              from.contains(where: \.isLetter), to.contains(where: \.isLetter) else { return nil }
        return (from, to)
    }

    /// Anchors use unchanged surrounding text. Edits outside the inserted span are ambiguous.
    public static func editedSpan(value: String, prefix: String, suffix: String) -> String? {
        guard value.hasPrefix(prefix), value.hasSuffix(suffix),
              value.utf16.count >= prefix.utf16.count + suffix.utf16.count else { return nil }
        let range = NSRange(location: prefix.utf16.count, length: value.utf16.count - prefix.utf16.count - suffix.utf16.count)
        return (value as NSString).substring(with: range)
    }
}

public struct DiskStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> FlowData {
        guard FileManager.default.fileExists(atPath: url.path) else { return FlowData() }
        return try JSONDecoder().decode(FlowData.self, from: Data(contentsOf: url))
    }
    public func save(_ data: FlowData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoded = try JSONEncoder().encode(data)
        try encoded.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
