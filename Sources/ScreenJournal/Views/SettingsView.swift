import JournalCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    let noteShortcutWorks: Bool
    let showGuide: () -> Void
    @AppStorage(Preferences.interval) private var interval = 10.0
    @AppStorage(Preferences.retentionDays) private var retentionDays = 30
    @AppStorage(Preferences.language) private var chosenLanguage = Language.default
    @Environment(\.language) private var language
    @State private var about = ""
    @State private var tasks: [String] = []
    @State private var screenshots = true
    @State private var keySaved = GatewayKey.isSaved
    @State private var newKey = ""
    @State private var keyStatus: KeyStatus = .idle
    /// Closed by default: the key is set up once, usually for her.
    @State private var showConnect = false

    enum KeyStatus: Equatable {
        case idle, checking, works
        case failed(String)
    }

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
                TextField(language("What you do"), text: $about, prompt: Text(language("I do marketing for clients, so Instagram is usually work.")), axis: .vertical)
                    .lineLimit(3...6)
                VStack(alignment: .leading, spacing: 8) {
                    Text(language("Kinds of task"))
                    TagField(tags: $tasks, fixed: TaskKind.defaults.map { .init(id: $0.name, name: language.name(ofKind: $0.name), meaning: language.meaning(of: $0)) },
                             prompt: language("Add your own, then press Return"))
                }
            } header: {
                Text(language("Your work"))
            } footer: {
                Text(language("Helps tell your work from the rest, and sort it. The outlined kinds are always there; point at one to see what it covers, click one of yours to edit it."))
            }

            Section {
                DisclosureGroup(isExpanded: $showConnect) {
                    keyRow
                    if !keySaved, case .failed(let message) = keyStatus { Text(message).foregroundStyle(.red) }
                    Toggle(language("Send screenshots too"), isOn: $screenshots)
                    Text(language("The key lets an AI model sort your sessions into kinds of task, every hour. It stays in this Mac's Keychain; Claude never sees it. Screenshots make the sorting much more accurate, and they're sent as they are: only a screen showing an API key is held back, and password managers are never captured."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } label: {
                    // The whole row opens it, not just the chevron.
                    HStack {
                        Text(language("Connect AI categorization"))
                        Spacer()
                        if keySaved { Text(language("Connected")).foregroundStyle(.secondary) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { showConnect.toggle() } }
                }
            }

            // Set once, if ever: at the bottom with the rest she rarely needs.
            Section {
                // Both languages, so it can be found whichever one is on.
                Picker("Idioma · Language", selection: $chosenLanguage) {
                    ForEach(Language.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                HStack {
                    Button(language("How It Works"), action: showGuide)
                    Button(language("Open Journal Folder"), action: model.openFolder)
                    Spacer()
                    if model.updater.isAvailable {
                        Button(language("Check for Updates"), action: model.updater.checkForUpdates)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .onChange(of: about) { save() }
        .onChange(of: tasks) { save() }
        .onChange(of: screenshots) { save() }
    }

    private var keyRow: some View {
        LabeledContent(language("AI Gateway key")) {
            if keySaved {
                HStack {
                    keyStatusText
                    Button(language("Check"), action: check).disabled(keyStatus == .checking)
                    Button(language("Disconnect"), action: removeKey)
                }
            } else {
                HStack {
                    SecureField("", text: $newKey, prompt: Text("vck_…"))
                        .labelsHidden()
                        .frame(width: 200)
                        .onSubmit(saveKey)
                    Button(language("Save"), action: saveKey).disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder private var keyStatusText: some View {
        switch keyStatus {
        case .idle: Text(language("Saved")).foregroundStyle(.secondary)
        case .checking: ProgressView().controlSize(.small)
        case .works: Text(language("Works")).foregroundStyle(.green)
        case .failed(let message): Text(message).foregroundStyle(.red).lineLimit(2).help(message)
        }
    }

    private func saveKey() {
        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        newKey = ""
        switch GatewayKey.save(key) {
        case .success:
            keySaved = true
            check()
        case .failure(let error):
            keyStatus = .failed(error.message)
        }
    }

    private func removeKey() {
        GatewayKey.remove()
        keySaved = false
        keyStatus = .idle
    }

    /// One tiny request about a made-up window, so a wrong key shows here rather than in tomorrow's run.
    private func check() {
        guard let key = GatewayKey.read() else { return removeKey() }
        keyStatus = .checking
        Task {
            switch await DecisionGateway(key: key).check() {
            case .success: keyStatus = .works
            case .failure(let error): keyStatus = .failed(error.message.hasPrefix("401") || error.message.hasPrefix("403") ? language("The gateway refused this key.") : error.message)
            }
        }
    }

    private func load() {
        guard case .success(let setup) = model.store.labelSetup() else { return }
        about = setup.about
        tasks = setup.tasks
        screenshots = setup.screenshots
    }

    private func save() {
        try? model.store.save(LabelSetup(about: about.trimmingCharacters(in: .whitespacesAndNewlines), tasks: tasks, screenshots: screenshots))
    }
}
