import Testing
@testable import JournalCore

private func line(_ text: String, x: Double, to maxX: Double, top: Double, height: Double = 0.014) -> TextLine {
    TextLine(text: text, minX: x, maxX: maxX, top: top, height: height)
}

/// WhatsApp Web in a browser, measured on real frames (1600×1035).
private let menuBar = [line("Zen", x: 0.03, to: 0.05, top: 0.009, height: 0.013), line("File", x: 0.06, to: 0.07, top: 0.009, height: 0.013)]
private let heading = line("WhatsApp", x: 0.17, to: 0.23, top: 0.056, height: 0.029)
private let dots = line(":", x: 0.36, to: 0.37, top: 0.058, height: 0.018)
private let address = line("web.whatsapp.com", x: 0.01, to: 0.09, top: 0.083, height: 0.013)

struct ChatHeaderTests {
    @Test func namesTheOpenGroupChat() {
        let lines = menuBar + [
            heading, dots, address,
            line("Forgia LFG!", x: 0.46, to: 0.51, top: 0.051, height: 0.017),
            line("Luciano, Nina, Ro, You", x: 0.46, to: 0.54, top: 0.069),
        ]
        #expect(ChatHeader.title("WhatsApp", lines: lines) == "Forgia LFG! — WhatsApp")
    }

    @Test func namesAOneToOneChat() {
        let lines = [heading, dots, address, line("Mariano Marini", x: 0.46, to: 0.53, top: 0.061)]
        #expect(ChatHeader.title("WhatsApp", lines: lines) == "Mariano Marini — WhatsApp")
    }

    @Test func aNotificationBannerIsNotAChat() {
        let lines = [heading, dots, address, line("Login Item Added", x: 0.82, to: 0.89, top: 0.058)]
        #expect(ChatHeader.title("WhatsApp", lines: lines) == "WhatsApp")
    }

    @Test func otherWindowsKeepTheirTitle() {
        let lines = [heading, line("Forgia LFG!", x: 0.46, to: 0.51, top: 0.051)]
        #expect(ChatHeader.title("Inbox - Gmail", lines: lines) == "Inbox - Gmail")
        #expect(ChatHeader.title(nil, lines: lines) == nil)
    }

    @Test func aKeyInTheHeaderIsRedacted() {
        let lines = [heading, line("vck_ABCDEFGHIJKLMNOP1234", x: 0.46, to: 0.6, top: 0.058)]
        #expect(ChatHeader.title("WhatsApp", lines: lines) == "[redacted] — WhatsApp")
    }
}

struct PlaceTests {
    @Test func aTerminalsFolderFromItsDocument() {
        let place = Place.from(document: "file:///Users/me/code/forgia-apps/verify/", pageURL: nil, addressBar: nil, home: "/Users/me")
        #expect(place == "~/code/forgia-apps/verify")
    }

    @Test func aPageKeepsItsAddressWithKeysRedacted() {
        let place = Place.from(document: nil, pageURL: "https://vercel.com/forgia/verify/settings?token=vck_ABCDEFGHIJKLMNOP1234", addressBar: nil, home: "/Users/me")
        #expect(place == "https://vercel.com/forgia/verify/settings?token=[redacted]")
    }

    @Test func otherwiseWhatTheAddressBarShows() {
        #expect(Place.from(document: nil, pageURL: nil, addressBar: "web.whatsapp.com", home: "/Users/me") == "web.whatsapp.com")
        #expect(Place.from(document: nil, pageURL: nil, addressBar: "Search or enter address", home: "/Users/me") == nil)
        #expect(Place.from(document: nil, pageURL: nil, addressBar: nil, home: "/Users/me") == nil)
    }
}
