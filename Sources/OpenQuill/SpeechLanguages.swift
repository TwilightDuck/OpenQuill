import SwiftUI
import WhisperKit

enum SpeechLanguages {
    static let codes = Constants.languageCodes
    static let parakeetCodes: Set<String> = ["bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it", "lv", "lt", "mt", "pl", "pt", "ro", "ru", "sk", "sl", "es", "sv", "uk"]
    static var sortedCodes: [String] {
        codes.sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
    }
    static func name(_ code: String) -> String {
        switch code {
        case "auto": return "Detect language"
        case "*": return "All languages"
        case "default": return "Use default"
        case "nl": return "Dutch / Flemish"
        case "zh": return "Chinese · Mandarin"
        case "yue": return "Chinese · Cantonese"
        case "jw": return "Javanese"
        case "unknown": return "Undetermined"
        default: return Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code.uppercased()
        }
    }
    static func detectedCode(_ code: String?) -> String {
        guard let code else { return "unknown" }
        let base = code.split(separator: "-").first.map(String.init) ?? code
        let normalized = base == "jv" ? "jw" : base
        return codes.contains(normalized) ? normalized : "unknown"
    }
}

extension SpeechModel {
    var languageCodes: Set<String> { self == .parakeet ? SpeechLanguages.parakeetCodes : SpeechLanguages.codes }
    func supports(_ language: String) -> Bool { language == "auto" || languageCodes.contains(language) }
    var languageCoverage: String { "\(languageCodes.count) languages · automatic detection" }
}

struct SpeechLanguagePicker: View {
    let title: String
    @Binding var selection: String
    var model: SpeechModel?
    var special: String? = "auto"
    @State private var showing = false
    @State private var search = ""

    private var options: [String] {
        let preferred = ["en", "nl"]
        let extras = special == "default" ? ["default", "auto"] : (special.map { [$0] } ?? [])
        let all = extras + preferred + SpeechLanguages.sortedCodes.filter { !preferred.contains($0) }
        guard !search.isEmpty else { return all }
        return all.filter { code in
            SpeechLanguages.name(code).localizedStandardContains(search)
                || code.localizedStandardContains(search)
                || (Locale(identifier: code).localizedString(forLanguageCode: code)?.localizedStandardContains(search) ?? false)
        }
    }
    var body: some View {
        Button {
            search = ""; showing = true
        } label: {
            HStack(spacing: 8) {
                Text(SpeechLanguages.name(selection)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
        }.accessibilityLabel(title).accessibilityValue(SpeechLanguages.name(selection))
            .sheet(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(title).font(.title2.weight(.semibold))
                        Spacer()
                        Button { showing = false } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("Close language selection").keyboardShortcut(.cancelAction)
                    }
                    TextField("Search languages or codes", text: $search).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Search languages")
                    List(options, id: \.self) { code in
                        Button {
                            selection = code; showing = false
                        } label: {
                            HStack {
                                Text(SpeechLanguages.name(code))
                                Spacer()
                                if let model, code != "*", code != "default", !model.supports(code) {
                                    Text("Whisper required").font(.caption).foregroundStyle(.secondary)
                                }
                                Image(systemName: selection == code ? "checkmark" : "circle")
                                    .foregroundStyle(selection == code ? Color.flowAccent : Color.clear)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).padding(.vertical, 4)
                    }.listStyle(.plain).overlay {
                        if options.isEmpty { ContentUnavailableView.search(text: search) }
                    }
                    if let model {
                        Text("\(model.title): \(model.languageCoverage). Whisper supports the full \(SpeechLanguages.codes.count)-language catalog. Accuracy varies by language and voice.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(24).frame(width: 440, height: 510).background(Color.flowCanvas)
            }
    }
}
