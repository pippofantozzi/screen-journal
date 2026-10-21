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
        #expect(WindowTitle.stable("~/Code — zsh") == "~/Code — zsh")
    }

    @Test func dropsUnreadCounters() {
        #expect(WindowTitle.stable("(1) WhatsApp") == "WhatsApp")
        #expect(WindowTitle.stable("(23) Inbox — Gmail") == "Inbox — Gmail")
        #expect(WindowTitle.stable("(99+) Slack") == "Slack")
        #expect(WindowTitle.stable("Inbox (12)") == "Inbox")
        #expect(WindowTitle.stable("● (3) Inbox") == "Inbox")
    }

    @Test func keepsParenthesesThatAreNotCounters() {
        #expect(WindowTitle.stable("Report (draft)") == "Report (draft)")
        #expect(WindowTitle.stable("(draft) Report") == "(draft) Report")
        #expect(WindowTitle.stable("Report (2).xlsx") == "Report (2).xlsx")
        #expect(WindowTitle.stable("(1)") == "(1)")
    }

    @Test func titleThatIsOnlyGlyphsIsNoTitle() {
        #expect(WindowTitle.stable("◐ ") == nil)
        #expect(WindowTitle.stable(nil) == nil)
    }
}
