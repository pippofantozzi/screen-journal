import JournalCore
import SwiftUI

/// What the journal captures, and what the AI is told about her work to sort it.
struct JournalSettings: View {
    let model: AppModel
    let noteShortcutWorks: Bool
    @AppStorage(Preferences.interval) private var interval = 10.0
    @AppStorage(Preferences.retentionDays) private var retentionDays = 30
    @Environment(\.language) private var language
    @State private var about = ""
    @State private var picked: [String] = []
    @State private var screenshots = true
    @State private var promptCopied = false

    var body: some View {
        Form {
            Section {
                Picker(language("Take a snapshot every"), selection: $interval) {
                    ForEach(Preferences.intervalOptions, id: \.self) { Text(language("%@ seconds", "\(Int($0))")).tag($0) }
                }
                Stepper(language("Keep the last %@ days", "\(retentionDays)"), value: $retentionDays, in: 3...180, step: 1)
            } header: {
                Text(language("Capture"))
            } footer: {
                Text(noteShortcutWorks
                    ? language("Press %@ in any app to note what's going on.", GlobalHotKey.note.label)
                    : language("Another app uses %@; note moments from the menu instead.", GlobalHotKey.note.label))
            }

            Section {
                // Label above, text from the left: beside its label a form field is right-aligned, where a typed space can't be seen.
                VStack(alignment: .leading, spacing: 8) {
                    Text(language("What you do"))
                    TextField("", text: $about, prompt: Text(language("I do marketing for clients, so Instagram is usually work.")), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(3...6)
                        .multilineTextAlignment(.leading)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(language("Kinds of task"))
                    KindPicker(picked: $picked, suggestions: TaskKind.suggestions.map {
                        .init(id: $0.name, name: language.name(ofKind: $0.name), meaning: language.meaning(of: $0))
                    })
                }
                Toggle(language("Send screenshots too"), isOn: $screenshots)
            } header: {
                Text(language("Your work"))
            } footer: {
                Text(language("Helps tell your work from the rest, and sort it. Pick only the kinds that fit your work: the fewer, the sharper the sorting. Anything that fits none goes under “other”. Point at a kind to see what it covers."))
            }

            Section {
                LabeledContent(language("Prompt for your agent")) {
                    Button(action: copyAgentPrompt) {
                        Label(promptCopied ? language("Copied") : language("Copy"), systemImage: promptCopied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .onChange(of: about) { save() }
        .onChange(of: picked) { save() }
        .onChange(of: screenshots) { save() }
    }

    private func load() {
        guard case .success(let setup) = model.store.labelSetup() else { return }
        about = setup.about
        picked = setup.picked
        screenshots = setup.screenshots
    }

    /// Where the journal lives and how to build on it, for whichever agent she pastes it into.
    private func copyAgentPrompt() {
        Clipboard.write(AgentBrief.prompt(root: model.store.root.path, language: language))
        withAnimation(.spring(duration: 0.3)) { promptCopied = true }
    }

    private func save() {
        try? model.store.save(LabelSetup(about: about.trimmingCharacters(in: .whitespacesAndNewlines), picked: picked, screenshots: screenshots))
        model.sortAfterEdits()
    }
}
