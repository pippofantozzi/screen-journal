import AppKit
import SwiftUI

struct ScreenJournalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: delegate.model, windows: delegate.windows)
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
        quitGracefullyOnSIGTERM()
        if model.isOnboarded {
            model.start()
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

    init(model: AppModel) {
        self.model = model
    }

    func showOnboarding(at step: OnboardingView.Step? = nil) {
        if let step { UserDefaults.standard.set(step.rawValue, forKey: OnboardingView.stepKey) }
        show("onboarding", title: "Welcome", size: CGSize(width: 520, height: 480), chromeless: true) {
            OnboardingView(
                model: self.model,
                onFinish: { [weak self] in self?.close("onboarding") },
                onTour: { [weak self] in
                    self?.close("onboarding")
                    self?.showGuide()
                }
            )
        }
    }

    func showGuide() {
        show("guide", title: "How Screen Journal Works", size: CGSize(width: 520, height: 560), chromeless: true) {
            GuideView { [weak self] in self?.close("guide") }
        }
    }

    func showSettings() {
        show("settings", title: "Screen Journal Settings", size: CGSize(width: 460, height: 420)) {
            SettingsView(model: self.model)
        }
    }

    func showNote() {
        let moment = model.currentMoment()
        show("note", title: "Note this moment", size: CGSize(width: 420, height: 170)) {
            NoteView { [weak self] text in
                self?.model.addNote(text, about: moment)
                self?.close("note")
            }
        }
    }

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
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        window.center()
        windows[id] = window
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.windows.removeValue(forKey: id) }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func close(_ id: String) {
        windows[id]?.close()
    }
}
