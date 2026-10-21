import Testing
@testable import JournalCore

struct WindowTitleTests {
    @Test func dropsLeadingSpinnerGlyphs() {
        #expect(WindowTitle.stable("◑ screen-journal-plan") == "screen-journal-plan")
        #expect(WindowTitle.stable("⠙ claude") == "claude")
        #expect(WindowTitle.stable("✳ Claude Code") == "Claude Code")
        #expect(WindowTitle.stable("● main.swift — Project") == "main.swift — Project")
    }

    @Test func keepsOrdinaryTitles() {
        #expect(WindowTitle.stable("Invoices.xlsx") == "Invoices.xlsx")
        #expect(WindowTitle.stable("(2) Inbox — Gmail") == "(2) Inbox — Gmail")
        #expect(WindowTitle.stable("~/Code — zsh") == "~/Code — zsh")
    }

    @Test func titleThatIsOnlyGlyphsIsNoTitle() {
        #expect(WindowTitle.stable("◐ ") == nil)
        #expect(WindowTitle.stable(nil) == nil)
    }
}
