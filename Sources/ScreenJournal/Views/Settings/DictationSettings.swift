import JournalCore
import SwiftUI

/// The key that starts dictation, the words it should know, and what it still needs to work.
struct DictationSettings: View {
    let dictation: DictationController
    @AppStorage(Preferences.dictationKey) private var key = DictationKey.rightCommand
    @AppStorage(Preferences.dictationLanguage) private var spoken = DictationLanguage.default
    @Environment(\.language) private var language
    @State private var words = Preferences.currentDictationWords
    @State private var draft = ""
    @State private var micAllowed = Microphone.isAllowed
    @State private var trusted = WindowContext.isTrusted

    var body: some View {
        Form {
            Section {
                Picker(language("Shortcut"), selection: $key) {
                    Text(language("Off")).tag(DictationKey.off)
                    Text(language("Right %@", DictationKey.rightCommand.symbol)).tag(DictationKey.rightCommand)
                    Text(language("Right %@", DictationKey.rightOption.symbol)).tag(DictationKey.rightOption)
                }
                if key != .off {
                    needs
                    LabeledContent(language("Write")) { steps(.key, .action(language("speak")), .key) }
                    LabeledContent(language("Edit")) { steps(.action(language("highlight")), .key, .action(language("say how")), .key) }
                }
            }

            Section {
                Picker(language("Language"), selection: $spoken) {
                    Text(language("Portuguese")).tag(DictationLanguage.portuguese)
                    Text(language("English")).tag(DictationLanguage.english)
                    Text(language("Automatic")).tag(DictationLanguage.automatic)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if !words.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(words, id: \.self) { chip($0) }
                        }
                    }
                    TextField("", text: $draft, prompt: Text(language("Add a name or term, then press Return")))
                        .labelsHidden()
                        .onSubmit(add)
                }
            } header: {
                Text(language("Words"))
            }
        }
        .formStyle(.grouped)
        .onChange(of: key) { dictation.use(key) }
        .onChange(of: words) { UserDefaults.standard.set(words, forKey: Preferences.dictationWords) }
        // Grants are given in System Settings; the rows go away as soon as they are.
        .task {
            while !Task.isCancelled {
                micAllowed = Microphone.isAllowed
                trusted = WindowContext.isTrusted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Only what's missing, each with the one button that fixes it.
    @ViewBuilder private var needs: some View {
        if !trusted {
            LabeledContent(language("Accessibility")) {
                Button(language("Allow…"), action: WindowContext.requestTrust)
            }
        }
        if !micAllowed {
            LabeledContent(language("Microphone")) {
                Button(language("Allow…")) {
                    Task { if Microphone.wasAsked { Microphone.openPrivacyPane() } else { _ = await Microphone.requestAccess() } }
                }
            }
        }
    }

    private enum Step: Hashable {
        case key
        case action(String)
    }

    /// The recipe as she'd do it: the key as a keycap, what she does between taps.
    private func steps(_ steps: Step...) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 { Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary) }
                switch step {
                case .key:
                    Text(language("Right %@", key.symbol))
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.5)))
                case .action(let words):
                    Text(words).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func chip(_ word: String) -> some View {
        HStack(spacing: 4) {
            Text(word)
            Button { withAnimation { words.removeAll { $0 == word } } } label: {
                Image(systemName: "xmark").font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(language("Delete %@", word))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.18)))
    }

    private func add() {
        withAnimation { words = DictationWords.adding(draft, to: words) }
        draft = ""
    }
}
