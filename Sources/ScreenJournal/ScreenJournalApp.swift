import AppKit
import JournalCore
import SwiftUI

struct ScreenJournalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            Localized { MenuContent(model: delegate.model, windows: delegate.windows) }
        } label: {
            StatusIcon(model: delegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    lazy var windows = WindowPresenter(model: model)
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if RunningApp.anotherIsRunning {
            NSApp.terminate(nil)
            return
        }
        quitGracefullyOnSIGTERM()
        windows.startNoteShortcut()
        if model.isOnboarded {
            model.start()
            if model.shouldAskForContext {
                model.markAskedForContext()
                windows.showOnboarding(at: .context)
            }
        } else {
            windows.showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    /// `kill`/`pkill` would otherwise drop the open frames; route them through a normal quit so they're written.
    private func quitGracefullyOnSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignal = source
    }
}

/// Owns the app's few AppKit windows; a menu-bar app has no window scene to lean on.
@MainActor
final class WindowPresenter {
    private let model: AppModel
    private var windows: [String: NSWindow] = [:]
    private var noteShortcut: GlobalHotKey?

    init(model: AppModel) {
        self.model = model
    }

    func showOnboarding(at step: OnboardingView.Step? = nil) {
        if let step { UserDefaults.standard.set(step.rawValue, forKey: OnboardingView.stepKey) }
        show("onboarding", title: language("Welcome"), size: CGSize(width: 520, height: 480), chromeless: true) {
            OnboardingView(
                model: self.model,
                onFinish: { [weak self] in self?.close("onboarding") }
            )
        }
    }

    func showGuide() {
        show("guide", title: language("How Screen Journal Works"), size: CGSize(width: 520, height: 560), chromeless: true) {
            GuideView { [weak self] in self?.close("guide") }
        }
    }

    func showWeek() {
        show("week", title: language("Your Week"), size: CGSize(width: 600, height: 680)) {
            WeekView(store: self.model.store)
        }
    }

    func showSettings() {
        show("settings", title: language("Screen Journal Settings"), size: CGSize(width: 500, height: 660)) {
            SettingsView(model: self.model, noteShortcutWorks: self.noteShortcutWorks) { [weak self] in self?.showGuide() }
        }
    }

    /// Stays off when another app already holds the combination; the menu item still works.
    func startNoteShortcut() {
        let key = GlobalHotKey.note
        noteShortcut = GlobalHotKey(keyCode: key.keyCode, modifiers: key.modifiers) { [weak self] in self?.showNote() }
    }

    var noteShortcutWorks: Bool { noteShortcut != nil }

    /// A floating panel that takes typing without activating the app: her app stays in front,
    /// so the note is about what she was doing and the journal sees no app switch.
    func showNote() {
        if let existing = windows["note"] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let moment = model.currentMoment()
        let panel = NotePanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 420, height: 170)),
            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.title = language("Note this moment")
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: Localized { NoteView(
            onSave: { [weak self] text in
                self?.model.addNote(text, about: moment)
                self?.close("note")
            },
            onCancel: { [weak self] in self?.close("note") }
        ) })
        panel.center()
        track(panel, as: "note")
        panel.makeKeyAndOrderFront(nil)
    }

    /// Window titles are AppKit's, read once when a window opens.
    private var language: Language { Preferences.currentLanguage }

    private func show<Content: View>(_ id: String, title: String, size: CGSize, chromeless: Bool = false, content: () -> Content) {
        if let existing = windows[id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: chromeless ? [.titled, .closable, .fullSizeContentView] : [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = chromeless
        window.titleVisibility = chromeless ? .hidden : .visible
        let root = content()
        window.contentView = NSHostingView(rootView: Localized { root })
        window.center()
        track(window, as: id)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func track(_ window: NSWindow, as id: String) {
        window.isReleasedWhenClosed = false
        windows[id] = window
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.windows.removeValue(forKey: id) }
        }
    }

    private func close(_ id: String) {
        windows[id]?.close()
    }
}

/// Panels only become key for text fields when asked to; this one always may.
private final class NotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
