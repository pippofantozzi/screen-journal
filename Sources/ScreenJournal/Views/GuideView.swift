import AppKit
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

    static let pages: [Page] = [
        Page(symbol: "sparkles", tint: .purple, title: "What Screen Journal does", points: [
            Point(symbol: "camera.aperture", text: "Every 10 seconds it looks at your screen and saves a snapshot, but only if something changed."),
            Point(symbol: "text.viewfinder", text: "It reads the text on screen and notes which app and window you're in."),
            Point(symbol: "lock.laptopcomputer", text: "Everything stays in the ScreenJournal folder on this Mac. Nothing is uploaded."),
        ]),
        Page(symbol: "menubar.rectangle", tint: .blue, title: "The menu bar icon", points: [
            Point(symbol: "camera.aperture", text: "Aperture: journaling."),
            Point(symbol: "moon.zzz", text: "Moon: resting while you're away or the screen is locked."),
            Point(symbol: "pause.circle", text: "Pause: you paused it."),
            Point(symbol: "exclamationmark.triangle", text: "Warning: it needs your help. Click it and choose Turn Screen Access Back On."),
        ]),
        Page(symbol: "pause.fill", tint: .orange, title: "Pause any time", points: [
            Point(symbol: "timer", text: "Menu → Pause → 15 minutes, 1 hour, or until you resume."),
            Point(symbol: "hand.raised", text: "Use it for anything private: personal chats, health, shopping, surprises 🎁."),
            Point(symbol: "play.fill", text: "Timed pauses resume by themselves. Otherwise choose Resume."),
        ]),
        Page(symbol: "square.and.pencil", tint: .pink, title: "Leave a note", points: [
            Point(symbol: "lightbulb", text: "When something feels tedious or repetitive, choose Note This Moment."),
            Point(symbol: "quote.bubble", text: "A few words is plenty: \"copying orders into the sheet again\"."),
            Point(symbol: "star", text: "Notes are the most useful clue Claude gets. Ten notes in a week beats none."),
        ]),
        Page(symbol: "eye.slash", tint: .indigo, title: "What's never saved", points: [
            Point(symbol: "key", text: "Password managers are blanked out, and nothing is saved while one is in front."),
            Point(symbol: "lock", text: "Nothing is saved while the screen is locked or you've been away for 2 minutes."),
            Point(symbol: "gearshape", text: "Settings → Never capture lets you add any app, like your bank or messages."),
            Point(symbol: "trash", text: "Days older than 30 are deleted automatically. You can change that in Settings."),
        ]),
        Page(symbol: "wand.and.stars", tint: .teal, title: "After a week: ask Claude", points: [
            Point(symbol: "terminal", text: "Open Terminal, paste the line below, and press Return."),
            Point(symbol: "text.bubble", text: "Then type: find what I should automate."),
            Point(symbol: "hammer", text: "Claude reads your journal, suggests automations, and can build the ones you pick."),
        ], command: "cd ~/ScreenJournal && claude"),
        Page(symbol: "questionmark.circle", tint: .green, title: "If something seems off", points: [
            Point(symbol: "exclamationmark.triangle", text: "macOS sometimes asks again for screen permission. Just allow it."),
            Point(symbol: "arrow.down.circle", text: "Updates install by themselves. Menu → Check for Updates if you're curious."),
            Point(symbol: "folder", text: "Menu → Open Journal Folder shows everything that was saved."),
            Point(symbol: "heart", text: "Still stuck? Ask Filippo. 💌"),
        ]),
    ]

    let onClose: () -> Void
    @State private var index = 0

    private var page: Page { Self.pages[index] }
    private var isLast: Bool { index == Self.pages.count - 1 }

    var body: some View {
        Walkthrough(symbol: page.symbol, tint: page.tint, index: index, count: Self.pages.count, height: 560) {
            PageBody(page: page)
        }
        .overlay(alignment: .bottom) { navigation }
    }

    private var navigation: some View {
        HStack {
            Button("Back") { go(index - 1) }
                .opacity(index == 0 ? 0 : 1)
                .disabled(index == 0)
                .keyboardShortcut(.leftArrow, modifiers: [])
            Spacer()
            Button(isLast ? "Done" : "Next") { isLast ? onClose() : go(index + 1) }
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
        guard Self.pages.indices.contains(next) else { return }
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

    var body: some View {
        HStack {
            Text(command).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                withAnimation(.spring(duration: 0.3)) { copied = true }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .tint(tint)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.1)))
    }
}
