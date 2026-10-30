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
        windows.startWhatsAppTap()
        windows.startDictation()
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
    private var whatsappTap: KeyWatcher?
    let dictation = DictationController()

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
        show("settings", title: language("Screen Journal Settings"), size: CGSize(width: 700, height: 600)) {
            SettingsView(model: self.model, dictation: self.dictation, noteShortcutWorks: self.noteShortcutWorks) { [weak self] in self?.showGuide() }
        }
    }

    /// Stays off when another app already holds the combination; the menu item still works.
    func startNoteShortcut() {
        let key = GlobalHotKey.note
        noteShortcut = GlobalHotKey(keyCode: key.keyCode, modifiers: key.modifiers) { [weak self] in self?.showNote() }
    }

    var noteShortcutWorks: Bool { noteShortcut != nil }

    /// Tapping Left ⌘ alone while WhatsApp is in front; anywhere else it's in too many shortcuts to mean this.
    /// Like dictation, it hears other apps' keys only with the Accessibility grant it had at launch.
    func startWhatsAppTap() {
        let key = KeyWatcher.leftCommand
        whatsappTap = KeyWatcher(keyCode: key.keyCode, deviceMask: key.deviceMask) { [weak self] in
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == WhatsAppWindow.bundleID else { return }
            self?.showWhatsAppExport()
        }
    }

    func startDictation() {
        // Any Keychain prompt shows now, not in the middle of her first dictation.
        _ = GatewayKey.current()
        dictation.use(Preferences.currentDictationKey)
    }

    /// A floating panel that takes typing without activating the app: her app stays in front,
    /// so the note is about what she was doing and the journal sees no app switch.
    func showNote() {
        if let existing = windows["note"] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let moment = model.currentMoment()
        showPanel("note", title: language("Note this moment")) {
            NoteView(
                onSave: { [weak self] text in
                    self?.model.addNote(text, about: moment)
                    self?.close("note")
                },
                onCancel: { [weak self] in self?.close("note") }
            )
        }
    }

    /// Over WhatsApp without activating Screen Journal, with the chat open there already picked.
    func showWhatsAppExport() {
        if let existing = windows["whatsapp"] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let chats = WhatsAppStore.chats()
        let open = WhatsApp.chat(named: WhatsAppWindow.openChatName(), among: (try? chats.get()) ?? [])
        showPanel("whatsapp", title: language("Export WhatsApp chat")) {
            WhatsAppExportView(chats: chats, open: open) { [weak self] in self?.close("whatsapp") }
        }
    }

    /// A floating panel that takes typing without activating the app.
    private func showPanel<Content: View>(_ id: String, title: String, content: () -> Content) {
        let panel = NotePanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 420, height: 170)),
            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.title = title
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        let root = content()
        panel.contentView = NSHostingView(rootView: Localized { root })
        panel.center()
        track(panel, as: id)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Window titles are AppKit's, read once when a window opens.
    private var language: Language { Preferences.currentLanguage }

    private func show<Content: View>(_ id: String, title: String, size: CGSize, chromeless: Bool = false, content: () -> Content) {
        if let existing = windows[id] {
            bringForward(existing)
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
        bringForward(window)
    }

    /// In front even when macOS declines to activate the app, as it may while another app is in use.
    private func bringForward(_ window: NSWindow) {
        window.orderFrontRegardless()
        window.makeKey()
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
