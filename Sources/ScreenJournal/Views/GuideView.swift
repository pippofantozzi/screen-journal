import AppKit
import JournalCore
import SwiftUI

/// "How Screen Journal Works": a tour she can reopen from the menu whenever she has a doubt.
struct GuideView: View {
    struct Point {
        let symbol: String
        let text: String
    }

    struct Page {
        let symbol: String
        let tint: Color
        let title: String
        let points: [Point]
        var command: String? = nil
    }

    static func pages(in language: Language) -> [Page] { [
        Page(symbol: "sparkles", tint: .purple, title: language("What Screen Journal does"), points: [
            Point(symbol: "camera.aperture", text: language("Every 10 seconds it looks at your screen and saves a snapshot, but only if something changed.")),
            Point(symbol: "text.viewfinder", text: language("It reads the text on screen and notes which app and window you're in.")),
            Point(symbol: "lock.laptopcomputer", text: language("Everything stays in the ScreenJournal folder on this Mac. Only when AI categorization is connected are short excerpts sent, to sort your sessions.")),
        ]),
        Page(symbol: "menubar.rectangle", tint: .blue, title: language("The menu bar icon"), points: [
            Point(symbol: "camera.aperture", text: language("Aperture: journaling.")),
            Point(symbol: "moon.zzz", text: language("Moon: resting while you're away or the screen is locked.")),
            Point(symbol: "pause.circle", text: language("Pause: you paused it.")),
            Point(symbol: "exclamationmark.triangle", text: language("Warning: it needs your help. Click it and choose Turn Screen Access Back On.")),
        ]),
        Page(symbol: "pause.fill", tint: .orange, title: language("Pause any time"), points: [
            Point(symbol: "timer", text: language("Menu → Pause → 15 minutes, 1 hour, or until you resume.")),
            Point(symbol: "hand.raised", text: language("Use it for anything private: personal chats, health, shopping, surprises 🎁.")),
            Point(symbol: "play.fill", text: language("Timed pauses resume by themselves. Otherwise choose Resume.")),
        ]),
        Page(symbol: "square.and.pencil", tint: .pink, title: language("Leave a note"), points: [
            Point(symbol: "lightbulb", text: language("When something feels tedious or repetitive, press ⌥Space in any app.")),
            Point(symbol: "quote.bubble", text: language("A few words is plenty: \"copying orders into the sheet again\".")),
            Point(symbol: "star", text: language("Notes are the most useful clue Claude gets. Ten notes in a week beats none.")),
        ]),
        Page(symbol: "eye.slash", tint: .indigo, title: language("What's never saved"), points: [
            Point(symbol: "key", text: language("Password managers are blanked out, and nothing is saved while one is in front.")),
            Point(symbol: "lock", text: language("Nothing is saved while the screen is locked or you've been away for 2 minutes.")),
            Point(symbol: "trash", text: language("Days older than 30 are deleted automatically. You can change that in Settings.")),
        ]),
        Page(symbol: "wand.and.stars", tint: .teal, title: language("After a week: ask Claude"), points: [
            Point(symbol: "terminal", text: language("Open Terminal, paste the line below, and press Return.")),
            Point(symbol: "text.bubble", text: language("Then type: find what I should automate.")),
            Point(symbol: "hammer", text: language("Claude reads your journal, suggests automations, and can build the ones you pick.")),
        ], command: "cd ~/ScreenJournal && claude"),
        Page(symbol: "questionmark.circle", tint: .green, title: language("If something seems off"), points: [
            Point(symbol: "exclamationmark.triangle", text: language("macOS sometimes asks again for screen permission. Just allow it.")),
            Point(symbol: "arrow.down.circle", text: language("Updates install by themselves. Settings → Check for Updates if you're curious.")),
            Point(symbol: "folder", text: language("Settings → Open Journal Folder shows everything that was saved.")),
            Point(symbol: "heart", text: language("Still stuck? Ask Filippo. 💌")),
        ]),
    ] }

    let onClose: () -> Void
    @State private var index = 0
    @Environment(\.language) private var language

    private var pages: [Page] { Self.pages(in: language) }
    private var page: Page { pages[index] }
    private var isLast: Bool { index == pages.count - 1 }

    var body: some View {
        Walkthrough(symbol: page.symbol, tint: page.tint, index: index, count: pages.count, height: 560) {
            PageBody(page: page)
        }
        .overlay(alignment: .bottom) { navigation }
    }

    private var navigation: some View {
        HStack {
            Button(language("Back")) { go(index - 1) }
                .opacity(index == 0 ? 0 : 1)
                .disabled(index == 0)
                .keyboardShortcut(.leftArrow, modifiers: [])
            Spacer()
            Button(isLast ? language("Done") : language("Next")) { isLast ? onClose() : go(index + 1) }
                .buttonStyle(.borderedProminent)
                .tint(page.tint)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .background(Button("") { go(index + 1) }.keyboardShortcut(.rightArrow, modifiers: []).opacity(0))
    }

    private func go(_ next: Int) {
        guard pages.indices.contains(next) else { return }
        withAnimation(.spring(duration: 0.55, bounce: 0.2)) { index = next }
    }
}

private struct PageBody: View {
    let page: GuideView.Page
    @State private var shown = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(page.title)
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity)
            ForEach(Array(page.points.enumerated()), id: \.offset) { i, point in
                Label {
                    Text(point.text).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: point.symbol).foregroundStyle(page.tint).frame(width: 22)
                }
                .opacity(i < shown ? 1 : 0)
                .offset(y: i < shown ? 0 : 8)
            }
            if let command = page.command {
                CopyableCommand(command: command, tint: page.tint)
                    .opacity(shown > page.points.count - 1 ? 1 : 0)
            }
        }
        .task {
            // Points arrive one after another so each gets read.
            for i in 1...page.points.count {
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.spring(duration: 0.4, bounce: 0.3)) { shown = i }
            }
        }
    }
}

private struct CopyableCommand: View {
    let command: String
    let tint: Color
    @State private var copied = false
    @Environment(\.language) private var language

    var body: some View {
        HStack {
            Text(command).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                withAnimation(.spring(duration: 0.3)) { copied = true }
            } label: {
                Label(copied ? language("Copied") : language("Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .tint(tint)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.1)))
    }
}
