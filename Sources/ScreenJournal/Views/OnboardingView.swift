import JournalCore
import SwiftUI

/// Four calm steps: what this is, screen access, chats and folders, ready. Open at login is turned on at the end.
/// The step is persisted so a relaunch (needed after granting access) lands back where she was.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, screenAccess, context, ready

        var symbol: String {
            switch self {
            case .welcome: "sparkles"
            case .screenAccess: "rectangle.dashed.badge.record"
            case .context: "person.2.wave.2"
            case .ready: "checkmark"
            }
        }

        var tint: Color {
            switch self {
            case .welcome: .purple
            case .screenAccess: .blue
            case .context: .indigo
            case .ready: .green
            }
        }
    }

    static let stepKey = "onboardingStep"

    let model: AppModel
    let onFinish: () -> Void
    @Environment(\.language) private var language

    @AppStorage(OnboardingView.stepKey) private var stepRaw = Step.welcome.rawValue

    private var step: Step { Step(rawValue: stepRaw) ?? .welcome }

    var body: some View {
        Walkthrough(symbol: step.symbol, tint: step.tint, index: step.rawValue, count: Step.allCases.count) {
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            StepCard(
                title: language("Hi! Let's learn how you work"),
                message: language("Screen Journal quietly takes a snapshot of your screen every few seconds, but only when something changed. Everything stays on this Mac. After a week or two, Claude can read it and suggest ways to automate the boring parts."),
                action: (language("Get Started"), { advance(to: .screenAccess) })
            )
        case .screenAccess:
            ScreenAccessStep { advance(to: .context) }
        case .context:
            ContextStep { advance(to: .ready) }
        case .ready:
            ReadyStep {
                model.markOnboarded()
                onFinish()
            }
        }
    }

    private func advance(to next: Step) {
        withAnimation(.spring(duration: 0.55, bounce: 0.2)) { stepRaw = next.rawValue }
    }
}

private struct StepCard: View {
    let title: String
    let message: String
    let action: (label: String, run: () -> Void)

    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action.label, action: action.run)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 10)
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// Polls the grant once a second; offers a relaunch because macOS often applies it only to a new process.
private struct ScreenAccessStep: View {
    let onGranted: () -> Void
    @State private var granted = SystemAccess.hasScreenAccess
    @State private var asked = false
    @Environment(\.language) private var language

    var body: some View {
        VStack(spacing: 14) {
            Text(language("Allow screen snapshots")).font(.title2.weight(.semibold))
            Text(markdown: language("macOS will ask you to turn on Screen Journal under **Screen & System Audio Recording**. Flip the switch, then come back here."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if granted {
                GrantedBadge(text: language("Access granted"))
            } else {
                Button(asked ? language("Open System Settings Again") : language("Open System Settings")) {
                    asked = true
                    SystemAccess.requestScreenAccess()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 10)

                if asked {
                    Button(language("Already switched it on? Restart Screen Journal")) { SystemAccess.relaunch() }
                        .buttonStyle(.link)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut, value: asked)
        .task {
            while !Task.isCancelled && !granted {
                try? await Task.sleep(for: .seconds(1))
                withAnimation(.spring(duration: 0.5, bounce: 0.4)) { granted = SystemAccess.hasScreenAccess }
            }
            try? await Task.sleep(for: .seconds(1))
            onGranted()
        }
    }
}

/// Optional: the journal works without it, it just can't tell chats or folders apart.
private struct ContextStep: View {
    let onDone: () -> Void
    @State private var granted = WindowContext.isTrusted
    @Environment(\.language) private var language

    var body: some View {
        VStack(spacing: 14) {
            Text(language("Know which chat and which page")).font(.title2.weight(.semibold))
            Text(markdown: language("Turn on Screen Journal under **Accessibility**, so the journal also notes which chat, website or folder is open."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if granted {
                GrantedBadge(text: language("Turned on"))
            } else {
                Button(language("Open System Settings")) { WindowContext.requestTrust() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 10)
                Button(language("Skip for Now"), action: onDone).buttonStyle(.link)
            }
        }
        .task {
            while !Task.isCancelled && !granted {
                try? await Task.sleep(for: .seconds(1))
                withAnimation(.spring(duration: 0.5, bounce: 0.4)) { granted = WindowContext.isTrusted }
            }
            try? await Task.sleep(for: .seconds(1))
            onDone()
        }
    }
}

/// Turns on open at login by itself, so the two weeks have no holes; says so only when macOS refuses.
private struct ReadyStep: View {
    let onStart: () -> Void
    @State private var loginFailed = false
    @Environment(\.language) private var language

    var body: some View {
        StepCard(
            title: language("You're all set"),
            message: language("Look for the little aperture in your menu bar. Press ⌥Space in any app to jot down what's going on, especially when something feels tedious. It starts by itself when you log in; pause it from the menu any time.")
                + (loginFailed ? "\n\n" + language("macOS didn't let it open at login: move the app to Applications and open it again.") : ""),
            action: (language("Start Journaling"), onStart)
        )
        .task {
            do { try SystemAccess.enableOpenAtLogin() } catch { loginFailed = true }
        }
    }
}

private struct GrantedBadge: View {
    let text: String
    @State private var appeared = false

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.headline)
            .foregroundStyle(.green)
            .symbolEffect(.bounce, value: appeared)
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            .padding(.top, 10)
            .onAppear { withAnimation(.spring(duration: 0.5, bounce: 0.5)) { appeared = true } }
    }
}
