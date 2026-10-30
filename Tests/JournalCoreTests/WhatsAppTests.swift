import Foundation
import Testing
@testable import JournalCore

struct WhatsAppTests {
    let utc = TimeZone(identifier: "UTC")!
    let noon = Date(timeIntervalSince1970: 1_793_361_600) // 2026-10-30 12:00:00 UTC

    func chat(_ id: Int64, _ name: String, minutesAgo: Double = 0) -> WhatsApp.Chat {
        WhatsApp.Chat(id: id, name: name, lastMessage: noon.addingTimeInterval(-minutesAgo * 60))
    }

    @Test func findsTheOpenChatByName() {
        let chats = [chat(1, "Bru"), chat(2, "Forgia LFG! 🚀")]
        #expect(WhatsApp.chat(named: "Forgia LFG! 🚀", among: chats)?.id == 2)
    }

    @Test func ignoresDirectionMarksAndCase() {
        let chats = [chat(1, "\u{200E}You"), chat(2, "\u{202A}+55 11 91615-4460\u{202C}")]
        #expect(WhatsApp.chat(named: "you", among: chats)?.id == 1)
        #expect(WhatsApp.chat(named: "+55 11 91615-4460", among: chats)?.id == 2)
    }

    @Test func twoChatsWithOneNamePicksTheLatest() {
        let chats = [chat(1, "Ro", minutesAgo: 60), chat(2, "Ro", minutesAgo: 1)]
        #expect(WhatsApp.chat(named: "Ro", among: chats)?.id == 2)
    }

    @Test func noNameOrNoMatchIsNoChat() {
        #expect(WhatsApp.chat(named: nil, among: [chat(1, "Bru")]) == nil)
        #expect(WhatsApp.chat(named: "Bruno", among: [chat(1, "Bru")]) == nil)
    }

    @Test func writesTextLikeWhatsAppsOwnExport() {
        let export = WhatsApp.export([
            WhatsApp.Message(date: noon, from: .member(nil), text: "Oi", media: nil),
            WhatsApp.Message(date: noon.addingTimeInterval(65), from: .you, text: "Tudo bem?\nE aí", media: nil),
        ], chat: "Bru", timeZone: utc)
        #expect(export.transcript == """
        [30/10/2026, 12:00:00] Bru: Oi
        [30/10/2026, 12:01:05] You: Tudo bem?
        E aí

        """)
        #expect(export.files.isEmpty)
        #expect(export.missing == 0)
    }

    @Test func groupMembersSpeakUnderTheirOwnNames() {
        let export = WhatsApp.export([
            WhatsApp.Message(date: noon, from: .member("\u{200E}Ro"), text: "Kkkk", media: nil),
        ], chat: "Forgia & Lyna", timeZone: utc)
        #expect(export.transcript == "[30/10/2026, 12:00:00] Ro: Kkkk\n")
    }

    @Test func attachesDownloadedMediaWithNumberedNames() {
        let export = WhatsApp.export([
            WhatsApp.Message(date: noon, from: .you, text: "look", media: .init(kind: .photo, file: "Media/x/a/b/1.jpg")),
            WhatsApp.Message(date: noon, from: .member(nil), text: nil, media: .init(kind: .audio, file: "Media/x/c/d/2.opus")),
        ], chat: "Bru", timeZone: utc)
        #expect(export.transcript == """
        [30/10/2026, 12:00:00] You: <attached: 00000001-PHOTO-2026-10-30-12-00-00.jpg> look
        [30/10/2026, 12:00:00] Bru: <attached: 00000002-AUDIO-2026-10-30-12-00-00.opus>

        """)
        #expect(export.files == [
            .init(source: "Media/x/a/b/1.jpg", name: "00000001-PHOTO-2026-10-30-12-00-00.jpg"),
            .init(source: "Media/x/c/d/2.opus", name: "00000002-AUDIO-2026-10-30-12-00-00.opus"),
        ])
    }

    @Test func mediaNeverDownloadedIsOmittedAndCounted() {
        let export = WhatsApp.export([
            WhatsApp.Message(date: noon, from: .member(nil), text: nil, media: .init(kind: .video, file: nil)),
        ], chat: "Bru", timeZone: utc)
        #expect(export.transcript == "[30/10/2026, 12:00:00] Bru: video omitted\n")
        #expect(export.files.isEmpty)
        #expect(export.missing == 1)
    }

    @Test func messageTypesThatCarryNoContentAreLeftOut() {
        #expect(WhatsApp.content(ofType: 0) == .text)
        #expect(WhatsApp.content(ofType: 7) == .text)
        #expect(WhatsApp.content(ofType: 1) == .media(.photo))
        #expect(WhatsApp.content(ofType: 3) == .media(.audio))
        #expect(WhatsApp.content(ofType: 6) == nil)
        #expect(WhatsApp.content(ofType: 59) == nil)
        #expect(WhatsApp.exportedTypes.sorted() == [0, 1, 2, 3, 7, 8, 11, 15])
    }

    @Test func archiveIsNamedForTheChatAndMinute() {
        #expect(WhatsApp.archiveName(chat: "Forgia LFG! 🚀", at: noon, timeZone: utc) == "Forgia LFG! 🚀 2026-10-30 12.00")
        #expect(WhatsApp.archiveName(chat: "\u{202A}a/b: c\u{202C}", at: noon, timeZone: utc) == "a-b- c 2026-10-30 12.00")
    }
}
