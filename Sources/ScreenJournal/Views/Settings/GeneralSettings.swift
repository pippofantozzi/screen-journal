import JournalCore
import SwiftUI

/// What the journal and dictation share: the AI key, the language, the folder, updates. Set up once, if ever.
struct GeneralSettings: View {
    let model: AppModel
    let showGuide: () -> Void
    @AppStorage(Preferences.language) private var chosenLanguage = Language.default
    @Environment(\.language) private var language
    @State private var keySaved = GatewayKey.isSaved
    @State private var newKey = ""
    @State private var keyStatus: KeyStatus = .idle

    enum KeyStatus: Equatable {
        case idle, checking, works
        case failed(String)
    }

    var body: some View {
        Form {
            Section {
                keyRow
                if !keySaved, case .failed(let message) = keyStatus { Text(message).foregroundStyle(.red) }
            } header: {
                Text(language("AI"))
            }

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
}
