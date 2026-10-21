import Testing
@testable import JournalCore

struct TextDeltaTests {
    @Test func identicalTextHasNoNewLines() {
        #expect(TextDelta.newLines("a\nb", seen: TextDelta.lineSet("a\nb")) == [])
    }

    @Test func findsTheOneNewLine() {
        #expect(TextDelta.newLines("a\nb\nc", seen: ["a", "c"]) == ["b"])
    }

    @Test func reorderedLinesAreNotNew() {
        #expect(TextDelta.newLines("b\na", seen: ["a", "b"]) == [])
    }

    @Test func linesSeenEarlierInTheVisitAreNotNew() {
        var seen = TextDelta.lineSet("chat A\nhello")
        let first = TextDelta.newLines("chat B\nbye", seen: seen)
        seen.formUnion(first)
        #expect(first == ["chat B", "bye"])
        #expect(TextDelta.newLines("chat A\nhello\nagain", seen: seen) == ["again"])
    }

    @Test func ignoresWhitespaceOnlyLinesAndTrims() {
        #expect(TextDelta.newLines("  \n  x  \n\t", seen: ["x"]) == [])
        #expect(TextDelta.newLines("  y  \n", seen: ["x"]) == ["y"])
        #expect(TextDelta.lineSet("  x \n\n y") == ["x", "y"])
    }

    @Test func collapsesDuplicatesKeepingOrder() {
        #expect(TextDelta.newLines("c\nb\nc\nb", seen: ["a"]) == ["c", "b"])
    }
}
