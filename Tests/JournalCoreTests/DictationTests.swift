import Foundation
import Testing
@testable import JournalCore

private func json(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

struct DictationIntentTests {
    @Test func aSelectionMakesTheSpeechAnInstruction() {
        #expect(DictationIntent(selection: "Dear Ana,") == .edit(selection: "Dear Ana,"))
    }

    @Test func noSelectionOrOnlySpaceMeansWrite() {
        #expect(DictationIntent(selection: nil) == .write)
        #expect(DictationIntent(selection: " \n\t") == .write)
    }
}

struct DictationWordsTests {
    @Test func addingTrimsAndSkipsBlanksAndRepeatsInAnyCase() {
        #expect(DictationWords.adding("  Forgia ", to: ["Notion"]) == ["Notion", "Forgia"])
        #expect(DictationWords.adding("notion", to: ["Notion"]) == ["Notion"])
        #expect(DictationWords.adding(" ", to: ["Notion"]) == ["Notion"])
    }

    @Test func theListStopsAtItsLimit() {
        let full = (0..<DictationWords.limit).map { "w\($0)" }
        #expect(DictationWords.adding("one more", to: full) == full)
    }
}

struct ModifierTapTests {
    /// Which events completed a tap, fed in order to one detector.
    private func taps(_ events: [(ModifierTap.Event, TimeInterval)]) -> [Bool] {
        var tap = ModifierTap()
        return events.map { tap.feed($0.0, at: $0.1) }
    }

    @Test func aQuickPressAndReleaseAloneIsATap() {
        #expect(taps([(.down, 10), (.up, 10.15)]) == [false, true])
    }

    @Test func anotherKeyWhileHeldIsAShortcutNotATap() {
        #expect(taps([(.down, 10), (.other, 10.05), (.up, 10.1)]) == [false, false, false])
    }

    @Test func holdingTooLongIsNotATap() {
        #expect(taps([(.down, 10), (.up, 10 + ModifierTap.longest + 0.01)]) == [false, false])
    }

    @Test func aReleaseWithoutAPressIsNotATap() {
        #expect(taps([(.up, 10), (.down, 11), (.up, 11.1), (.up, 11.2)]) == [false, false, true, false])
    }
}

struct WAVTests {
    @Test func theHeaderDescribes16BitMonoPCM() {
        let wav = WAV.encode(samples: [1, -1], sampleRate: 16_000)
        #expect(wav.count == 48)
        #expect(String(decoding: wav[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8..<16], as: UTF8.self) == "WAVEfmt ")
        #expect(String(decoding: wav[36..<40], as: UTF8.self) == "data")
        #expect(Array(wav[4..<8]) == [40, 0, 0, 0])       // file size minus 8
        #expect(Array(wav[22..<24]) == [1, 0])            // mono
        #expect(Array(wav[24..<28]) == [0x80, 0x3E, 0, 0]) // 16 000 Hz
        #expect(Array(wav[34..<36]) == [16, 0])           // bits per sample
        #expect(Array(wav[40..<44]) == [4, 0, 0, 0])      // data size
        #expect(Array(wav[44..<48]) == [1, 0, 0xFF, 0xFF])
    }
}

struct TranscriptionTests {
    @Test func theRequestGivesTheLanguageAndBiasesTowardTheWords() throws {
        let body = try json(Transcription.request(audio: Data([1, 2, 3]), words: ["Forgia"], language: .portuguese, zeroRetention: true))
        #expect(body["audio"] as? String == "AQID")
        #expect(body["mediaType"] as? String == "audio/wav")
        let options = try #require(body["providerOptions"] as? [String: Any])
        let mistral = try #require(options["mistral"] as? [String: Any])
        #expect(mistral["language"] as? String == "pt")
        #expect(mistral["contextBias"] as? [String] == ["Forgia"])
        let gateway = try #require(options["gateway"] as? [String: Any])
        #expect(gateway["zeroDataRetention"] as? Bool == true)
        #expect(gateway["disallowPromptTraining"] as? Bool == true)
    }

    @Test func automaticLeavesTheLanguageToTheModelAndNoWordsSendsNoBias() throws {
        let body = try json(Transcription.request(audio: Data(), words: [], language: .automatic, zeroRetention: true))
        let mistral = try #require((body["providerOptions"] as? [String: Any])?["mistral"] as? [String: Any])
        #expect(mistral["language"] == nil)
        #expect(mistral["contextBias"] == nil)
    }

    @Test func voiceNotesGoAsTheirOwnFormat() throws {
        let body = try json(Transcription.request(audio: Data(), mediaType: Transcription.mediaType(ofFile: "a/b.opus"), words: [], language: .automatic, zeroRetention: true))
        #expect(body["mediaType"] as? String == "audio/ogg")
        #expect(Transcription.mediaType(ofFile: "x.M4A") == "audio/mp4")
        #expect(Transcription.mediaType(ofFile: "x.mp3") == "audio/mpeg")
        #expect(Transcription.mediaType(ofFile: "x.wav") == "audio/wav")
    }

    @Test func eachLanguageHasTheCodeTheTranscriberExpects() {
        #expect(DictationLanguage.allCases.map(\.code) == ["pt", "en", nil])
        #expect(DictationLanguage.default == .portuguese)
    }

    @Test func theReplyGivesTheTrimmedText() {
        #expect(Transcription.text(Data(#"{"text":" Olá, Ana. ","language":"pt"}"#.utf8)) == .success("Olá, Ana."))
    }

    @Test func aReplyWithoutTextIsAFailure() {
        guard case .failure = Transcription.text(Data(#"{"error":{"message":"nope"}}"#.utf8)) else {
            Issue.record("expected a failure")
            return
        }
    }
}

struct SilenceTests {
    @Test func aRecordingWithNoPeakAboveTheFloorIsSilent() {
        #expect(Silence.isSilent([0, 40, -60, 100]))
        #expect(Silence.isSilent([]))
        #expect(!Silence.isSilent([0, 40, -2_000, 100]))
    }
}

struct RewriteTests {
    private func messages(_ intent: DictationIntent, words: [String] = []) throws -> [[String: String]] {
        let body = try json(Rewrite.request(model: "m", intent: intent, transcript: "say this", words: words, zeroRetention: true))
        return try #require(body["messages"] as? [[String: String]])
    }

    @Test func writingTidiesTheTranscript() throws {
        let sent = try messages(.write)
        #expect(sent[0]["content"]?.hasPrefix(Rewrite.writeInstructions) == true)
        #expect(sent[1]["content"]?.contains("say this") == true)
    }

    @Test func editingSendsTheSelectionAndTheInstruction() throws {
        let sent = try messages(.edit(selection: "Dear Ana"))
        #expect(sent[0]["content"]?.hasPrefix(Rewrite.editInstructions) == true)
        #expect(sent[1]["content"]?.contains("Dear Ana") == true)
        #expect(sent[1]["content"]?.contains("say this") == true)
    }

    @Test func theWordsAreGivenAsSpellings() throws {
        #expect(try messages(.write, words: ["Forgia", "Notion"])[0]["content"]?.contains("Forgia, Notion") == true)
        #expect(try messages(.write)[0]["content"] == Rewrite.writeInstructions)
    }

    @Test func theRequestRoutesFastWithoutReasoningAndKeepsNothing() throws {
        let body = try json(Rewrite.request(model: "m", intent: .write, transcript: "x", words: [], zeroRetention: true))
        #expect(body["model"] as? String == "m")
        #expect(body["temperature"] as? Double == 0)
        #expect((body["reasoning"] as? [String: Bool])?["enabled"] == false)
        let gateway = try #require((body["providerOptions"] as? [String: Any])?["gateway"] as? [String: Any])
        #expect(gateway["zeroDataRetention"] as? Bool == true)
        #expect(gateway["sort"] as? String == "tps")
    }

    @Test func theReplyIsTheMessageWithoutFencesOrTags() {
        func reply(_ content: String) -> Data {
            try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
        }
        #expect(Rewrite.text(reply(" Olá, Ana. ")) == .success("Olá, Ana."))
        #expect(Rewrite.text(reply("```\nOlá, Ana.\n```")) == .success("Olá, Ana."))
        #expect(Rewrite.text(reply("<text>Olá, Ana.</text>")) == .success("Olá, Ana."))
    }

    @Test func aReplyWithoutAMessageIsAFailure() {
        guard case .failure = Rewrite.text(Data(#"{"choices":[]}"#.utf8)) else {
            Issue.record("expected a failure")
            return
        }
    }
}

struct LoudnessTests {
    private func tone(_ amplitude: Int16) -> [Int16] { (0..<1_600).map { $0 % 2 == 0 ? amplitude : -amplitude } }

    @Test func silenceIsZeroAndShoutingIsFull() {
        #expect(Loudness.level([]) == 0)
        #expect(Loudness.level(tone(0)) == 0)
        #expect(Loudness.level(tone(20_000)) == 1)
    }

    @Test func ordinarySpeechFillsMostOfTheRangeNotAFewPercent() {
        // About -30 dBFS: someone talking normally a little way from the mic.
        let level = Loudness.level(tone(1_000))
        #expect(level > 0.5 && level < 0.9)
    }

    @Test func louderIsAlwaysHigher() {
        let levels = [100, 300, 1_000, 3_000].map { Loudness.level(tone(Int16($0))) }
        #expect(levels == levels.sorted() && Set(levels).count == levels.count)
    }
}
