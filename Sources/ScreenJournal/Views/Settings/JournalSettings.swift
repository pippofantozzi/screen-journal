import AppKit
import JournalCore
import SwiftUI
import UniformTypeIdentifiers

/// What the journal captures, privacy exclusions, and what the AI is told about her work to sort it.
struct JournalSettings: View {
    let model: AppModel
    let noteShortcutWorks: Bool
    @AppStorage(Preferences.interval) private var interval = 10.0
    @AppStorage(Preferences.retentionDays) private var retentionDays = 30
    @AppStorage(Preferences.autoTidy) private var autoTidy = true
    @Environment(\.language) private var language
    @State private var about = ""
    @State private var picked: [String] = []
    @State private var screenshots = true
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?
    @State private var promptCopied = false
    @State private var excludedApps = Preferences.currentExcludedApps
    @State private var excludedKeywords = Preferences.currentExcludedKeywords
    @State private var keywordDraft = ""

    var body: some View {
        Form {
            Section {
                Picker(language("Take a snapshot every"), selection: $interval) {
                    ForEach(Preferences.intervalOptions, id: \.self) { Text(language("%@ seconds", "\(Int($0))")).tag($0) }
                }
                Stepper(language("Keep the last %@ days", "\(retentionDays)"), value: $retentionDays, in: 3...180, step: 1)
                Toggle(language("Slim screenshots after 7 days"), isOn: $autoTidy)
            } header: {
                Text(language("Capture"))
            } footer: {
                Text(noteShortcutWorks
                    ? language("Press %@ in any app to note what's going on.", GlobalHotKey.note.label)
                    : language("Another app uses %@; note moments from the menu instead.", GlobalHotKey.note.label))
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(language("Excluded apps"))
                        Spacer()
                        Button(language("Add App…"), action: pickApp)
                    }
                    if !excludedApps.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(excludedApps, id: \.self) { appChip($0) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(language("Private window keywords"))
                    if !excludedKeywords.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(excludedKeywords, id: \.self) { keywordChip($0) }
                        }
                    }
                    TextField("", text: $keywordDraft, prompt: Text(language("e.g. bank name or portal, then press Return")))
                        .labelsHidden()
                        .onSubmit(addKeyword)
                }
            } header: {
                Text(language("Privacy"))
            } footer: {
                Text(language("Excluded apps are blanked out and never captured. Any window whose title matches a keyword is skipped too."))
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
        .onDisappear(perform: flushSave)
        .onChange(of: about) { if loaded { scheduleSave() } }
        .onChange(of: picked) { if loaded { saveNow() } }
        .onChange(of: screenshots) { if loaded { saveNow() } }
        .onChange(of: excludedApps) { UserDefaults.standard.set(excludedApps, forKey: Preferences.excludedApps) }
        .onChange(of: excludedKeywords) { UserDefaults.standard.set(excludedKeywords, forKey: Preferences.excludedKeywords) }
    }

    private func appChip(_ bundleID: String) -> some View {
        let name = appName(for: bundleID)
        return HStack(spacing: 4) {
            Text(name)
            Button { withAnimation { excludedApps.removeAll { $0 == bundleID } } } label: {
                Image(systemName: "xmark").font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(language("Delete %@", name))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.18)))
        .help(bundleID)
    }

    private func keywordChip(_ keyword: String) -> some View {
        HStack(spacing: 4) {
            Text(keyword)
            Button { withAnimation { excludedKeywords.removeAll { $0 == keyword } } } label: {
                Image(systemName: "xmark").font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(language("Delete %@", keyword))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.18)))
    }

    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(filePath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier, !excludedApps.contains(bundleID) else { continue }
            withAnimation { excludedApps.append(bundleID) }
        }
    }

    private func addKeyword() {
        let trimmed = keywordDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !excludedKeywords.contains(where: { $0.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame })
        else {
            keywordDraft = ""
            return
        }
        withAnimation { excludedKeywords.append(trimmed) }
        keywordDraft = ""
    }

    private func load() {
        loaded = false
        excludedApps = Preferences.currentExcludedApps
        excludedKeywords = Preferences.currentExcludedKeywords
        if case .success(let setup) = model.store.labelSetup() {
            about = setup.about
            picked = setup.picked
            screenshots = setup.screenshots
        }
        DispatchQueue.main.async { loaded = true }
    }

    /// Where the journal lives and how to build on it, for whichever agent she pastes it into.
    private func copyAgentPrompt() {
        Clipboard.write(AgentBrief.prompt(root: model.store.root.path, language: language))
        withAnimation(.spring(duration: 0.3)) { promptCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.spring(duration: 0.3)) { promptCopied = false }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func flushSave() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        saveNow()
    }

    private func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        try? model.store.save(LabelSetup(about: about.trimmingCharacters(in: .whitespacesAndNewlines), picked: picked, screenshots: screenshots))
        model.sortAfterEdits()
    }
}
