import JournalCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    let noteShortcutWorks: Bool
    let showGuide: () -> Void
    @AppStorage(Preferences.interval) private var interval = 10.0
    @AppStorage(Preferences.retentionDays) private var retentionDays = 30
    @State private var about = ""
    @State private var tasks: [String] = []
    @State private var look = false
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
                Picker("Take a snapshot every", selection: $interval) {
                    ForEach(Preferences.intervalOptions, id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                }
                Stepper("Keep the last \(retentionDays) days", value: $retentionDays, in: 3...180, step: 1)
            } header: {
                Text("Capture")
            } footer: {
                Text(noteShortcutWorks
                    ? "Press \(GlobalHotKey.note.label) in any app to note what's going on."
                    : "Another app uses \(GlobalHotKey.note.label); note moments from the menu instead.")
            }

            Section {
                TextField("What you do", text: $about, prompt: Text("I do marketing for clients, so Instagram is usually work."), axis: .vertical)
                    .lineLimit(3...6)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kinds of task")
                    TagField(tags: $tasks, fixed: TaskKind.defaults.map { ($0.name, $0.description) }, prompt: "Add your own, then press Return")
                }
            } header: {
                Text("Your work")
            } footer: {
                Text("Helps tell your work from the rest, and sort it. The outlined kinds are always there; point at one to see what it covers, click one of yours to edit it.")
            }

            Section {
                DisclosureGroup(isExpanded: $showConnect) {
                    keyRow
                    if !keySaved, case .failed(let message) = keyStatus { Text(message).foregroundStyle(.red) }
                    Toggle("Show screenshots when a window has little text", isOn: $look)
                    Text("The key lets an AI model sort your sessions into kinds of task. It stays in this Mac's Keychain; Claude never sees it. "
                        + "Screenshots help with design tools, photos and video, but they're sent as they are: nothing on them can be hidden.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } label: {
                    // The whole row opens it, not just the chevron.
                    HStack {
                        Text("Connect AI categorization")
                        Spacer()
                        if keySaved { Text("Connected").foregroundStyle(.secondary) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { showConnect.toggle() } }
                }
            }

            Section {
                HStack {
                    Button("How It Works", action: showGuide)
                    Button("Open Journal Folder", action: model.openFolder)
                    Spacer()
                    if model.updater.isAvailable {
                        Button("Check for Updates", action: model.updater.checkForUpdates)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .onChange(of: about) { save() }
        .onChange(of: tasks) { save() }
        .onChange(of: look) { save() }
    }

    private var keyRow: some View {
        LabeledContent("AI Gateway key") {
            if keySaved {
                HStack {
                    keyStatusText
                    Button("Check", action: check).disabled(keyStatus == .checking)
                    Button("Disconnect", action: removeKey)
                }
            } else {
                HStack {
                    SecureField("", text: $newKey, prompt: Text("vck_…"))
                        .labelsHidden()
                        .frame(width: 200)
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey).disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder private var keyStatusText: some View {
        switch keyStatus {
        case .idle: Text("Saved").foregroundStyle(.secondary)
        case .checking: ProgressView().controlSize(.small)
        case .works: Text("Works").foregroundStyle(.green)
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
            case .failure(let error): keyStatus = .failed(error.message.hasPrefix("401") || error.message.hasPrefix("403") ? "The gateway refused this key." : error.message)
            }
        }
    }

    private func load() {
        guard case .success(let setup) = model.store.labelSetup() else { return }
        about = setup.about
        tasks = setup.tasks
        look = setup.look
    }

    private func save() {
        try? model.store.save(LabelSetup(about: about.trimmingCharacters(in: .whitespacesAndNewlines), tasks: tasks, look: look))
    }
}
