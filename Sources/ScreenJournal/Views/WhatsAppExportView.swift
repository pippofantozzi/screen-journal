import AppKit
import JournalCore
import SwiftUI

/// Left ⌘ in WhatsApp: the open chat's last messages, with their photos, videos and transcribed voice notes, as a zip in Downloads.
struct WhatsAppExportView: View {
    let chats: Result<[WhatsApp.Chat], WhatsAppStore.Failure>
    let onDone: () -> Void
    @State private var chat: WhatsApp.Chat?
    @State private var search = ""
    @State private var transcribeVoiceNotes = true
    @AppStorage(Preferences.whatsappLast) private var count = 200
    @State private var state = SaveState.ready
    @State private var progress: (done: Int, total: Int)?
    @State private var exportTask: Task<Void, Never>?
    @Environment(\.language) private var language

    enum SaveState: Equatable {
        case ready, saving
        case saved(WhatsAppArchive.Saved)
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
                TextField(language("Search chats…"), text: $search)
                    .textFieldStyle(.roundedBorder)
                    .disabled(state == .saving)
                List(choices(all), selection: $chat) { item in
                    Text(item.name).lineLimit(1).tag(item)
                }
                .listStyle(.bordered)
                .frame(minHeight: 110, maxHeight: 150)
                .disabled(state == .saving)
                HStack {
                    Text(language("Last"))
                    TextField("", value: $count, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .onSubmit(save)
                        .disabled(state == .saving)
                    Text(language("messages"))
                    Spacer()
                    Toggle(language("Transcribe voice notes"), isOn: $transcribeVoiceNotes)
                        .disabled(state == .saving)
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
                    Button(language("Cancel"), action: cancelExport).keyboardShortcut(.cancelAction)
                    Button(language("Export"), action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(chat == nil || count < 1 || state == .saving)
                }
            }
        }
        .padding(20)
        .onDisappear { exportTask?.cancel() }
    }

    /// Searches across all chats when typing; otherwise shows the 50 latest plus the currently selected chat.
    private func choices(_ all: [WhatsApp.Chat]) -> [WhatsApp.Chat] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return Array(all.filter { $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }.prefix(50))
        }
        let recent = Array(all.prefix(50))
        guard let chat, !recent.contains(chat) else { return recent }
        return [chat] + recent
    }

    private var statusLine: String? {
        switch state {
        case .ready: nil
        case .saving:
            if let progress, progress.total > 0 {
                language("Transcribing voice notes (%@/%@)…", "\(progress.done)", "\(progress.total)")
            } else {
                language("Saving…")
            }
        case .saved(let saved):
            [saved.missing > 0 ? language("Saved. %@ media files were never downloaded to this Mac and are marked omitted.", "\(saved.missing)") : nil,
             saved.untranscribed > 0 ? language("%@ voice notes couldn't be transcribed.", "\(saved.untranscribed)") : nil]
                .compactMap { $0 }.joined(separator: " ")
        case .failed(let failure): message(failure)
        }
    }

    private func message(_ failure: WhatsAppArchive.Failure) -> String {
        switch failure {
        case .store(.notInstalled): language("WhatsApp for Mac isn't set up on this Mac.")
        case .store(.unreadable(let reason)): language("Can't read WhatsApp's messages: %@", reason)
        case .writing(let reason): language("Couldn't save the zip: %@", reason)
        case .cancelled: language("Export cancelled.")
        }
    }

    private func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        onDone()
    }

    /// Transcribing voice notes and copying media can take a while, so it runs off the main thread; Finder shows the zip when it's done.
    private func save() {
        guard let chat, count > 0, state != .saving else { return }
        state = .saving
        progress = nil
        let count = count
        let transcribe = transcribeVoiceNotes
        exportTask = Task {
            let result = await WhatsAppArchive.save(chat, last: count, transcribeVoiceNotes: transcribe) { done, total in
                Task { @MainActor in
                    self.progress = (done, total)
                }
            }
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let saved):
                NSWorkspace.shared.activateFileViewerSelecting([saved.zip])
                if saved.missing == 0 && saved.untranscribed == 0 { onDone() } else { state = .saved(saved) }
            case .failure(.cancelled):
                state = .ready
            case .failure(let failure):
                state = .failed(failure)
            }
        }
    }
}
