import Foundation

public struct SpokenSnippet: Codable, Identifiable, Sendable {
    public var id: UUID
    public var trigger: String
    public var replacement: String
    public var enabled: Bool
    public init(id: UUID = UUID(), trigger: String, replacement: String, enabled: Bool = true) {
        self.id = id; self.trigger = Self.normalized(trigger)
        self.replacement = replacement; self.enabled = enabled
    }
    public static func normalized(_ trigger: String) -> String {
        trigger.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    public var valid: Bool {
        !trigger.isEmpty && trigger.count <= 80 && trigger.contains(where: \.isLetter)
            && !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && replacement.count <= 10_000
    }
}

public enum SnippetProcessing {
    public static func expand(_ text: String, snippets: [SpokenSnippet], language: String) -> String {
        let terms = snippets.filter { $0.enabled && $0.valid }.sorted { $0.trigger.count > $1.trigger.count }
        return TextProcessing.replaceTerms(text, terms: terms.map { ($0.trigger, $0.replacement) }, language: language)
    }
    public static func matchingTriggers(_ text: String, snippets: [SpokenSnippet], language: String) -> [String] {
        snippets.filter { $0.enabled && $0.valid && TextProcessing.replaceTerms(text, terms: [($0.trigger, "")], language: language) != text }.map(\.trigger)
    }
}
