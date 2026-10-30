import AppKit
import JournalCore
import SwiftUI

/// Left ⌘ in WhatsApp: the open chat's last messages, with their photos, videos and voice notes, as a zip in Downloads.
struct WhatsAppExportView: View {
    let chats: Result<[WhatsApp.Chat], WhatsAppStore.Failure>
    let onDone: () -> Void
    @State private var chat: WhatsApp.Chat?
    @AppStorage(Preferences.whatsappLast) private var count = 200
    @State private var state = SaveState.ready
    @Environment(\.language) private var language

    enum SaveState: Equatable {
        case ready, saving
        case saved(missing: Int)
        case failed(WhatsAppArchive.Failure)
    }

    /// `open` is preselected; otherwise the most recent chat.
    init(chats: Result<[WhatsApp.Chat], WhatsAppStore.Failure>, open: WhatsApp.Chat?, onDone: @escaping () -> Void) {
        self.chats = chats
        self.onDone = onDone
        _chat = State(initialValue: open ?? (try? chats.get())?.first)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch chats {
            case .success(let all):
                Picker(language("Chat"), selection: $chat) {
                    ForEach(choices(all)) { Text($0.name).tag(Optional($0)) }
                }
                HStack {
                    Text(language("Last"))
                    TextField("", value: $count, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .onSubmit(save)
                    Text(language("messages"))
                }
            case .failure(let failure):
                Text(message(.store(failure)))
            }
            if let line = statusLine {
                Text(line).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                if case .saved = state {
                    Button(language("Done"), action: onDone).keyboardShortcut(.defaultAction)
                } else {
                    Button(language("Cancel"), action: onDone).keyboardShortcut(.cancelAction)
                    Button(language("Export"), action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(chat == nil || count < 1 || state == .saving)
                }
            }
        }
        .padding(20)
    }

    /// The 40 latest, plus the open chat when it's older.
    private func choices(_ all: [WhatsApp.Chat]) -> [WhatsApp.Chat] {
        let recent = Array(all.prefix(40))
        guard let chat, !recent.contains(chat) else { return recent }
        return [chat] + recent
    }

    private var statusLine: String? {
        switch state {
        case .ready, .saved(missing: 0): nil
        case .saving: language("Saving…")
        case .saved(let missing): language("Saved. %@ media files were never downloaded to this Mac and are marked omitted.", "\(missing)")
        case .failed(let failure): message(failure)
        }
    }

    private func message(_ failure: WhatsAppArchive.Failure) -> String {
        switch failure {
        case .store(.notInstalled): language("WhatsApp for Mac isn't set up on this Mac.")
        case .store(.unreadable(let reason)): language("Can't read WhatsApp's messages: %@", reason)
        case .writing(let reason): language("Couldn't save the zip: %@", reason)
        }
    }

    /// Copying media can take a few seconds, so it runs off the main thread; Finder shows the zip when it's done.
    private func save() {
        guard let chat, count > 0, state != .saving else { return }
        state = .saving
        let count = count
        Task {
            let result = await Task.detached { WhatsAppArchive.save(chat, last: count) }.value
            switch result {
            case .success(let saved):
                NSWorkspace.shared.activateFileViewerSelecting([saved.zip])
                if saved.missing == 0 { onDone() } else { state = .saved(missing: saved.missing) }
            case .failure(let failure):
                state = .failed(failure)
            }
        }
    }
}
