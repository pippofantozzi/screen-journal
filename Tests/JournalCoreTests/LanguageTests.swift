import Foundation
import Testing
@testable import JournalCore

struct LanguageTests {
    @Test func portugueseByDefaultAndEnglishIsTheKey() {
        #expect(Language.default == .portuguese)
        #expect(Language.english("Settings…") == "Settings…")
        #expect(Language.portuguese("Settings…") == "Ajustes…")
    }

    @Test func anUnknownPhraseStaysEnglish() {
        #expect(Language.portuguese("Never translated") == "Never translated")
    }

    @Test func fillsInTheBlanks() {
        #expect(Language.portuguese("Paused until %@", "14:30") == "Pausado até 14:30")
        #expect(Language.english("Paused until %@", "2:30 PM") == "Paused until 2:30 PM")
    }

    @Test func everyTranslationKeepsItsBlanks() {
        for (english, portuguese) in Language.portuguesePhrases {
            #expect(english.components(separatedBy: "%@").count == portuguese.components(separatedBy: "%@").count, "\(english)")
            #expect(!portuguese.isEmpty, "\(english)")
        }
    }

    @Test func theSuggestedKindsReadInPortugueseButStayEnglishInTheJournal() {
        for kind in TaskKind.suggestions + [TaskKind.other] {
            #expect(Language.portugueseKinds[kind.name] != nil, "\(kind.name)")
        }
        #expect(Language.portuguese.name(ofKind: "meeting") == "reunião")
        #expect(Language.english.name(ofKind: "meeting") == "meeting")
        #expect(Language.portuguese.name(ofKind: "reels") == "reels")
        #expect(Language.portuguese.meaning(of: TaskKind(name: "reels", description: "reels")) == "reels")
    }

    /// Every `language("…")` in the app has a Portuguese line, so she never meets English by accident.
    @Test func everyPhraseTheAppShowsIsTranslated() throws {
        let app = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Sources/ScreenJournal").standardized
        let files = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        let call = /language\("((?:[^"\\]|\\.)*)"/
        var phrases: Set<String> = []
        for file in files {
            for match in try String(contentsOf: file, encoding: .utf8).matches(of: call) {
                phrases.insert(String(match.1).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\n", with: "\n"))
            }
        }
        #expect(phrases.count > 100)
        let missing = phrases.filter { Language.portuguesePhrases[$0] == nil }.sorted()
        #expect(missing.isEmpty, "\(missing)")
    }
}
