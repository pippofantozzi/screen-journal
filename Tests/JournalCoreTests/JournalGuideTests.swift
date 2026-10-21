import Testing
@testable import JournalCore

struct JournalGuideTests {
    @Test func everySkillStartsWithFrontmatterNamedAfterItsFolderSoClaudeCodeDiscoversIt() {
        let skills = JournalGuide.files.filter { $0.path.hasSuffix("/SKILL.md") }
        #expect(skills.count == JournalGuide.skills.count)
        for skill in skills {
            let folder = skill.path.split(separator: "/").dropLast().last!
            #expect(skill.path.hasPrefix(".claude/skills/"))
            #expect(skill.contents.hasPrefix("---\nname: \(folder)\ndescription: "), "\(skill.path)")
        }
    }

    @Test func skillNamesAreUnique() {
        let names = JournalGuide.skills.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test func claudeMDPointsToEverySkill() {
        let claudeMD = JournalGuide.files.first { $0.path == "CLAUDE.md" }!.contents
        for name in JournalGuide.skills.map(\.name) {
            #expect(claudeMD.contains("`\(name)`"), "\(name)")
        }
    }

    /// After she forgets an app, a search of the folder should only find the helper that lists apps to skip.
    @Test func onlyTheJQHelpersNameChatApps() {
        for file in JournalGuide.files where file.path != ".claude/journal.jq" {
            #expect(!file.contents.lowercased().contains("whatsapp"), "\(file.path)")
        }
    }

    @Test func everyFileCarriesTheCurrentVersionMarker() {
        #expect(JournalGuide.files.allSatisfy { JournalGuide.isCurrent($0.contents) })
        #expect(!JournalGuide.isCurrent("<!-- screen-journal-guide v1 -->"))
    }
}
