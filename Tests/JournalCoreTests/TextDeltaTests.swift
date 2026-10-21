import Testing
@testable import JournalCore

struct TextDeltaTests {
    @Test func identicalTextHasNoNewLines() {
        #expect(TextDelta.newLines("a\nb", since: "a\nb") == [])
    }

    @Test func findsTheOneNewLine() {
        #expect(TextDelta.newLines("a\nb\nc", since: "a\nc") == ["b"])
    }

    @Test func reorderedLinesAreNotNew() {
        #expect(TextDelta.newLines("b\na", since: "a\nb") == [])
    }

    @Test func ignoresWhitespaceOnlyLinesAndTrims() {
        #expect(TextDelta.newLines("  \n  x  \n\t", since: "x") == [])
        #expect(TextDelta.newLines("  y  \n", since: "x") == ["y"])
    }

    @Test func collapsesDuplicatesKeepingOrder() {
        #expect(TextDelta.newLines("c\nb\nc\nb", since: "a") == ["c", "b"])
    }
}
