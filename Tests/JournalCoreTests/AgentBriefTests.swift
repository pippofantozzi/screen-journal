import Testing
@testable import JournalCore

struct AgentBriefTests {
    let prompt = AgentBrief.prompt(root: "/Users/ana/ScreenJournal", language: .portuguese)

    /// The agent may start anywhere, so every place it needs is spelled out from the root.
    @Test func pointsAtTheJournalByItsFullPath() {
        #expect(prompt.contains(#"cd "/Users/ana/ScreenJournal""#))
        for file in ["CLAUDE.md", "profile.md", "days/YYYY-MM-DD/", "reviews/", ".claude/sj", ".claude/journal.jq"] {
            #expect(prompt.contains("/Users/ana/ScreenJournal/\(file)"), "\(file)")
        }
    }

    @Test func namesEverySkillSoTheAgentReusesThem() {
        for name in JournalGuide.skills.map(\.name) {
            #expect(prompt.contains("`\(name)`"), "\(name)")
        }
    }

    @Test func buildsOnlyAfterUnderstandingInterviewAndApproval() {
        let gates = ["## Gate 1: Understand", "## Gate 2: Interview me", "## Gate 3: Propose, then wait for my approval", "## Gate 4: Build"]
        let positions = gates.compactMap { prompt.range(of: $0)?.lowerBound }
        #expect(positions.count == gates.count)
        #expect(positions == positions.sorted())
    }

    @Test func speaksHerLanguage() {
        #expect(prompt.contains("Talk to me in Português (Brasil)"))
        #expect(AgentBrief.prompt(root: "/r", language: .english).contains("Talk to me in English"))
    }
}
