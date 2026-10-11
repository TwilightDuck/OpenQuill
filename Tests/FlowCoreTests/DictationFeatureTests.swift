import Foundation
import Testing
import FlowCore

@Test func correctionsSurviveRestartAndStayInTheirAppAndLanguage() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = DiskStore(url: folder.appendingPathComponent("history.json"))
    var data = try store.load()
    let record = Dictation(original: "Send this to Acmey tomorrow.", text: "Send this to Acmey tomorrow.", appName: "Notes", bundleID: "notes", language: "en", audioSeconds: 3, processingSeconds: 0.3, delivery: "Inserted")
    data.dictations.append(record)
    data.learn(original: record.text, edited: "Send this to Acme tomorrow.", bundleID: "notes", language: "en")
    #expect(data.corrections.first?.enabled == false)
    data.learn(original: "Ask Acmey for an update.", edited: "Ask Acme for an update.", bundleID: "notes", language: "en")
    try store.save(data)
    let restored = try store.load()
    #expect(restored.dictations.first?.id == record.id)
    #expect(restored.dictations.first?.wordCount == 5)
    #expect(TextProcessing.clean("Contact Acmey and Acmeville.", corrections: restored.corrections, bundleID: "notes", language: "en", spokenPunctuation: false) == "Contact Acme and Acmeville.")
    #expect(TextProcessing.clean("Contact Acmey.", corrections: restored.corrections, bundleID: "mail", language: "en", spokenPunctuation: false) == "Contact Acmey.")
    #expect(TextProcessing.clean("Contact Acmey.", corrections: restored.corrections, bundleID: "notes", language: "nl", spokenPunctuation: false) == "Contact Acmey.")
    var chain = restored.corrections
    chain.append(Correction(from: "Acme", to: "Another name", bundleID: "notes", language: "en", observations: 2, enabled: true))
    #expect(TextProcessing.clean("Acmey and Acme", corrections: chain, bundleID: "notes", language: "en", spokenPunctuation: false) == "Acme and Another name")
    data.corrections[0].enabled = false
    data.corrections[0].userDisabled = true
    data.learn(original: "Ask acmey for an update.", edited: "Ask Acme for an update.", bundleID: "notes", language: "en")
    #expect(data.corrections.count == 1)
    #expect(data.corrections[0].enabled == false)
    let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func learningExcludesEditsOutsideTheDictatedSpanAndAmbiguousRewrites() {
    let prefix = "Existing private text 👋\n"
    let suffix = "\nKeep this untouched."
    let edited = TextProcessing.editedSpan(value: prefix + "Stuur dit naar Acme morgen." + suffix, prefix: prefix, suffix: suffix)
    #expect(edited == "Stuur dit naar Acme morgen.")
    #expect(TextProcessing.editedSpan(value: "Changed private text\nStuur dit naar Acme morgen." + suffix, prefix: prefix, suffix: suffix) == nil)
    #expect(TextProcessing.correction(original: "Send this tomorrow.", edited: "Send this tomorrow. Also add another paragraph.") == nil)
    #expect(TextProcessing.correction(original: "Send this to Acmey tomorrow.", edited: "") == nil)
    #expect(TextProcessing.correction(original: "Acmey", edited: "A new message", requireSharedContext: true) == nil)
    #expect(TextProcessing.correction(original: "Contact Acmey tomorrow.", edited: "Contact Acme tomorrow.", requireSharedContext: true)?.to == "Acme")
    var data = FlowData()
    for _ in 0..<2 { data.learn(original: "Mail Acmey today.", edited: "Mail Acme today.", bundleID: "mail", language: "en") }
    data.learn(original: "Mail Acmey today.", edited: "Mail Canon today.", bundleID: "mail", language: "en")
    #expect(data.corrections.allSatisfy { !$0.enabled })
    // An editor can expose text without a caret: infer only one complete inserted span.
    let context = TextProcessing.insertionContext(before: prefix + suffix, after: prefix + "Stuur dit naar Acmey morgen." + suffix, inserted: "Stuur dit naar Acmey morgen.")
    #expect(context?.prefix == prefix && context?.suffix == suffix)
    if let context, let edit = TextProcessing.editedSpan(value: prefix + "Stuur dit naar Acme morgen." + suffix, prefix: context.prefix, suffix: context.suffix) {
        var external = FlowData()
        external.learn(original: "Stuur dit naar Acmey morgen.", edited: edit, bundleID: "external-editor", language: "nl")
        #expect(external.corrections.first?.from == "Acmey")
        #expect(external.corrections.first?.to == "Acme")
        #expect(external.corrections.first?.enabled == false)
        external.learn(original: "Stuur dit naar Acmey morgen.", edited: edit, bundleID: "external-editor", language: "nl")
        #expect(TextProcessing.clean("Bel Acmey vandaag.", corrections: external.corrections, bundleID: "external-editor", language: "nl", spokenPunctuation: false) == "Bel Acme vandaag.")
    } else { Issue.record("The external field's corrected span was not recovered") }
    #expect(TextProcessing.insertionContext(before: "ha", after: "haha", inserted: "ha") == nil)
    #expect(TextProcessing.insertionContext(before: prefix + suffix, after: "Changed outside " + "Stuur dit naar Acmey morgen." + suffix, inserted: "Stuur dit naar Acmey morgen.") == nil)
}

@Test func dutchSpokenPunctuationAndCorrectionsPreserveUnicodeAndLiteralVocabulary() {
    let rules = [Correction(from: "acmey", to: "Acme $1", bundleID: "notes", language: "nl", observations: 2, enabled: true)]
    let result = TextProcessing.clean("Hallo Éline komma stuur dit naar acmey nieuwe alinea Tot morgen!", corrections: rules, bundleID: "notes", language: "nl", spokenPunctuation: true)
    #expect(result == "Hallo Éline, stuur dit naar Acme $1\n\nTot morgen!")
    #expect(TextProcessing.clean("We discussed a new line of products.", corrections: [], bundleID: "mail", language: "en", spokenPunctuation: false) == "We discussed a new line of products.")
    #expect(TextProcessing.clean("La commande s’appelle new line.", corrections: [], bundleID: "mail", language: "fr", spokenPunctuation: true) == "La commande s’appelle new line.")
    #expect(TextProcessing.clean("new line という名前です。", corrections: [], bundleID: "mail", language: "ja", spokenPunctuation: true) == "new line という名前です。")
}

@Test func taughtNamesApplyAcrossAppsAndOverrideOlderAutomaticGuesses() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = DiskStore(url: folder.appendingPathComponent("history.json"))
    var data = FlowData()
    let taught = data.teach(from: "acmey", to: "Acme")
    let empty = data.teach(from: "", to: "Acme")
    let unchanged = data.teach(from: "Acme", to: "Acme")
    let dutchName = data.teach(from: "eline", to: "Éline", language: "nl")
    #expect(taught && dutchName)
    #expect(!empty && !unchanged)
    data.corrections.append(Correction(from: "acmey", to: "Acmey Consulting", bundleID: "mail", language: "en", observations: 2, enabled: true))
    try store.save(data)
    let restored = try store.load()
    #expect(TextProcessing.clean("Mail acmey and Acmeville.", corrections: restored.corrections, bundleID: "codex", language: "en", spokenPunctuation: false) == "Mail Acme and Acmeville.")
    #expect(TextProcessing.clean("Mail acmey.", corrections: restored.corrections, bundleID: "mail", language: "en", spokenPunctuation: false) == "Mail Acme.")
    #expect(TextProcessing.clean("Vraag eline bij acmey.", corrections: restored.corrections, bundleID: "claude", language: "nl", spokenPunctuation: false) == "Vraag Éline bij Acme.")
    #expect(TextProcessing.clean("Ask eline.", corrections: restored.corrections, bundleID: "claude", language: "en", spokenPunctuation: false) == "Ask eline.")
}

@Test(arguments: [60.0, 180.0, 600.0, 1800.0])
func quietPauseStoppingWaitsForSpeechRespectsToggleAndHonorsTheChosenRecordingLimit(limit: Double) {
    var activity = RecordingActivity(maximumSeconds: limit)
    activity.append(rms: 0, duration: 10)
    #expect(!activity.shouldStop(silenceEnabled: true, delay: 5))
    activity.append(rms: 0.03, duration: 0.3)
    activity.append(rms: 0, duration: 4.9)
    #expect(!activity.shouldStop(silenceEnabled: true, delay: 5))
    activity.append(rms: 0.03, duration: 0.1) // Speech resumes: restart the pause countdown.
    activity.append(rms: 0, duration: 5.1)
    #expect(activity.shouldStop(silenceEnabled: true, delay: 5))
    #expect(!activity.shouldStop(silenceEnabled: false, delay: 5))
    #expect(!activity.shouldStop(silenceEnabled: true, delay: 8))
    activity.append(rms: 0, duration: limit - activity.seconds - 0.01)
    #expect(!activity.shouldStop(silenceEnabled: false, delay: 5))
    activity.append(rms: 0, duration: 0.02)
    #expect(activity.shouldStop(silenceEnabled: false, delay: 5))
}

@Test func speechProfileUsesRetainedDictationsAndExcludesImportedAudio() {
    func record(_ text: String, language: String, app: String = "notes") -> Dictation {
        Dictation(original: text, text: text, appName: "Notes", bundleID: app, language: language, audioSeconds: 6, processingSeconds: 0.2, delivery: "Inserted")
    }
    let english = record("Um you know this name.", language: "en")
    var dutch = record("Euh stuur dit naar Acmey.", language: "nl")
    dutch.corrected = "Euh stuur dit naar Acme."
    let profile = SpeechProfile(records: [english, dutch, record("uh uh uh", language: "en", app: "import")])
    #expect(profile.recordings.count == 2)
    #expect(profile.words == 10)
    #expect(profile.pace == 50)
    #expect(profile.correctedCount == 1)
    #expect(profile.languages.first?.name == "en")
    #expect(profile.phrases.first(where: { $0.name == "you know" })?.count == 1)
    #expect(!profile.phrases.contains(where: { $0.name == "uh" }))
    let multilingual = SpeechProfile(records: [
        record("明日の朝、駅で会いましょう。", language: "ja"),
        record("我喜欢苹果。明天见。", language: "zh"),
        record("ฉันชอบภาษาไทยมาก", language: "th"),
        record("Wir treffen uns um neun Uhr.", language: "de"),
        record("👋 !!!", language: "en")
    ])
    #expect(multilingual.languages.first(where: { $0.name == "ja" })!.words >= 5)
    #expect(multilingual.languages.first(where: { $0.name == "zh" })!.words >= 4)
    #expect(multilingual.languages.first(where: { $0.name == "th" })!.words >= 3)
    #expect(multilingual.languages.first(where: { $0.name == "en" })!.words == 0)
    #expect(multilingual.phrases.isEmpty) // German “um” is a preposition, not an English filler.
    var updated = record("明日の朝、駅で会いましょう。", language: "ja")
    updated.text = "Meet me tomorrow."
    #expect(updated.wordCount == 3)
    let restored = try? JSONDecoder().decode(Dictation.self, from: JSONEncoder().encode(updated))
    #expect(restored?.wordCount == 3)
}

@Test func multilingualNameCorrectionsKeepLiteralTextAndSurviveRestart() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = DiskStore(url: folder.appendingPathComponent("history.json"))
    let cases = [
        ("en", "Contact Acmey.", "Contact Acme.", "Acmey", "Acme", "Ask Acmey, then Acmeyville.", "Ask Acme, then Acmeyville."),
        ("ja", "明日は東京で山田さんに会います。", "明日は東京で山本さんに会います。", "山田", "山本", "山田さんに電話します。", "山本さんに電話します。"),
        ("zh", "明天联系Acmey讨论报告。", "明天联系Acme讨论报告。", "Acmey", "Acme", "请让Acmey给Acmeyville发邮件。", "请让Acme给Acmeyville发邮件。"),
        ("th", "พรุ่งนี้เราจะพบAcmeyที่สถานี", "พรุ่งนี้เราจะพบAcmeที่สถานี", "Acmey", "Acme", "เราจะพบAcmeyวันนี้", "เราจะพบAcmeวันนี้"),
        ("en", "Send this to New  Yorc  Cite tomorrow.", "Send this to New  York  City tomorrow.", "Yorc  Cite", "York  City", "Ask Yorc  Cite today.", "Ask York  City today.")
    ]
    for (language, original, edited, from, to, next, expected) in cases {
        var data = FlowData()
        for _ in 0..<2 { data.learn(original: original, edited: edited, bundleID: "scratch", language: language) }
        #expect(data.corrections.first?.from == from)
        #expect(data.corrections.first?.to == to)
        #expect(data.corrections.first?.enabled == true)
        try store.save(data)
        let restored = try store.load()
        #expect(TextProcessing.clean(next, corrections: restored.corrections, bundleID: "scratch", language: language, spokenPunctuation: false) == expected)
        #expect(TextProcessing.clean(next, corrections: restored.corrections, bundleID: "other-app", language: language, spokenPunctuation: false) == next)
    }
    #expect(TextProcessing.correction(original: "明日は東京です。", edited: "今日は大阪で会議です。", requireSharedContext: true) == nil)
    #expect(TextProcessing.correction(original: "Contact Acmey.", edited: "Contact Acmey!", requireSharedContext: true) == nil)
}

@Test func enterReadbackAcceptsOnlyTheFullInsertionAndPreservesExistingText() {
    #expect(TextProcessing.isExactInsertion(before: "", after: "Hello Éline 👋", inserted: "Hello Éline 👋"))
    #expect(TextProcessing.isExactInsertion(before: "Existing text.", after: "Existing text. Hello Éline 👋", inserted: " Hello Éline 👋"))
    #expect(TextProcessing.isExactInsertion(before: "Say hello then goodbye.", after: "Say hello then hello goodbye.", inserted: "hello "))
    #expect(!TextProcessing.isExactInsertion(before: "", after: "Hello É", inserted: "Hello Éline 👋"))
    #expect(!TextProcessing.isExactInsertion(before: "Existing text.", after: "Changed text. Hello Éline 👋", inserted: " Hello Éline 👋"))
    #expect(!TextProcessing.isExactInsertion(before: "Hello Éline 👋", after: "Hello Éline 👋", inserted: "Hello Éline 👋"))
}

@Test func spokenSnippetsSurviveUpgradeRestartAndExpandLiteralTextOnce() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = DiskStore(url: folder.appendingPathComponent("history.json"))
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(#"{"dictations":[],"corrections":[]}"#.utf8).write(to: store.url)
    var data = try store.load()
    #expect(data.snippets.isEmpty) // Older installations upgrade without losing history.
    let signature = "Kind regards,\nÉline 👋\nhttps://example.com/$1\\notes"
    data.snippets = [SpokenSnippet(trigger: "  my   signature  ", replacement: signature),
                     SpokenSnippet(trigger: "signature", replacement: "short signature"),
                     SpokenSnippet(trigger: "booking link", replacement: "https://example.com/book", enabled: false),
                     SpokenSnippet(trigger: "short signature", replacement: "Do not cascade")]
    try store.save(data)
    let restored = try store.load()
    #expect(restored.snippets.first?.replacement == signature)
    #expect(SnippetProcessing.expand("MY SIGNATURE; my signature. signature. booking link. my signatureville.", snippets: restored.snippets, language: "en") == "\(signature); \(signature). short signature. booking link. my signatureville.")
    #expect(Set(SnippetProcessing.matchingTriggers("My signature.", snippets: restored.snippets, language: "en")) == Set(["my signature", "signature"]))
    #expect(SnippetProcessing.expand("请说我的签名。", snippets: [SpokenSnippet(trigger: "我的签名", replacement: signature)], language: "zh") == "请说\(signature)。")
}

@Test func optionalCleanupRejectsLostProtectedContentAndKeepsUsefulProofreading() {
    let original = "Um send 12.50 euros to Éline using my signature tomorrow."
    #expect(CleanupValidation.accepts("Send 12.50 euros to Éline using my signature tomorrow.", original: original, protectedPhrases: ["Éline", "my signature"]))
    #expect(!CleanupValidation.accepts("Send 1250 euros to Éline using my signature tomorrow.", original: original, protectedPhrases: ["Éline", "my signature"]))
    #expect(!CleanupValidation.accepts("Send 12.50 euros to Eline tomorrow.", original: original, protectedPhrases: ["Éline", "my signature"]))
    #expect(!CleanupValidation.accepts("No, I will send the report tomorrow and call you afterward.", original: "No.", protectedPhrases: []))
    #expect(!CleanupValidation.accepts("", original: original, protectedPhrases: []))
    #expect(!CleanupValidation.accepts(String(repeating: "Extra information. ", count: 20), original: original, protectedPhrases: []))
}
