import Testing
@testable import JournalCore

struct JournalGuideTests {
    @Test func skillStartsWithFrontmatterSoClaudeCodeDiscoversIt() {
        let skill = JournalGuide.files.first { $0.path.hasSuffix("SKILL.md") }!.contents
        #expect(skill.hasPrefix("---\nname: find-automations\n"))
    }

    @Test func everyFileCarriesTheCurrentVersionMarker() {
        #expect(JournalGuide.files.allSatisfy { JournalGuide.isCurrent($0.contents) })
        #expect(!JournalGuide.isCurrent("<!-- screen-journal-guide v0 -->"))
    }
}
