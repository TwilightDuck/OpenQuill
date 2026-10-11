import SwiftUI
import FlowCore

struct SnippetsView: View {
    @Bindable var state: AppState
    @State private var draft: SpokenSnippet?
    @State private var trigger = ""
    @State private var replacement = ""
    @State private var invalid = false

    private func edit(_ snippet: SpokenSnippet) {
        trigger = snippet.trigger; replacement = snippet.replacement; invalid = false; draft = snippet
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Say less. Write exactly what you need.")
                            .font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-0.6)
                        Text("A short phrase becomes your saved text. Entirely on this Mac.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add snippet", systemImage: "plus") { edit(SpokenSnippet(trigger: "", replacement: "")) }.buttonStyle(.borderedProminent)
                }
                if state.data.snippets.isEmpty {
                    ContentUnavailableView("Your frequently used text, one phrase away", systemImage: "text.badge.plus",
                        description: Text("Try “my signature”, “booking link”, or “project introduction”. Add the exact text you want to insert, including links and line breaks."))
                }
                ForEach(state.data.snippets) { snippet in
                    HStack(alignment: .top, spacing: 14) {
                        Toggle("Enable \(snippet.trigger)", isOn: Binding(get: { snippet.enabled }, set: { state.setSnippet(snippet.id, enabled: $0) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("“\(snippet.trigger)”").font(.headline)
                            Text(snippet.replacement).font(.callout).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                        }
                        Spacer()
                        Button("Edit") { edit(snippet) }.buttonStyle(.borderless)
                        Button { state.removeSnippet(snippet.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).accessibilityLabel("Delete \(snippet.trigger) snippet")
                    }.flowCard()
                }
                Text("Choose a phrase you would deliberately say. Matching ignores case, respects word boundaries, and prefers longer triggers at the same position. Every occurrence expands once. Saved text is inserted literally, without AI rewriting or executing commands. Snippets apply across apps and languages, including private setup practice.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(30)
        }
        .sheet(item: $draft) { snippet in
            VStack(alignment: .leading, spacing: 18) {
                Text(snippet.trigger.isEmpty ? "Add a spoken snippet" : "Edit spoken snippet").font(.title2.bold())
                TextField("Phrase to say", text: $trigger).textFieldStyle(.roundedBorder).accessibilityLabel("Snippet trigger")
                Text("Text to insert").font(.headline)
                ZStack(alignment: .topLeading) {
                    if replacement.isEmpty { Text("Your exact text, including links and line breaks…").foregroundStyle(.secondary).padding(12) }
                    TextEditor(text: $replacement).font(.body).scrollContentBackground(.hidden).padding(8)
                        .accessibilityLabel("Snippet replacement")
                }.frame(height: 180).background(Color.flowSurface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.flowSeparator))
                Text("Up to 80 characters in the trigger and 10,000 in the replacement. Links, symbols and line breaks are preserved.").font(.caption).foregroundStyle(.secondary)
                if invalid { Text("Use a unique phrase with letters and a nonempty replacement within those limits.").font(.caption).foregroundStyle(Color.flowDanger) }
                HStack {
                    Spacer()
                    Button("Cancel") { draft = nil }.keyboardShortcut(.cancelAction)
                    Button("Save snippet") {
                        if state.saveSnippet(SpokenSnippet(id: snippet.id, trigger: trigger, replacement: replacement, enabled: snippet.enabled)) { draft = nil }
                        else { invalid = true }
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }.padding(26).frame(width: 500)
        }
    }
}
