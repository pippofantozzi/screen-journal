import SwiftUI

/// Four calm steps: what this is, screen access, open at login, ready.
/// The step is persisted so a relaunch (needed after granting access) lands back where she was.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, screenAccess, openAtLogin, ready

        var symbol: String {
            switch self {
            case .welcome: "sparkles"
            case .screenAccess: "rectangle.dashed.badge.record"
            case .openAtLogin: "power"
            case .ready: "checkmark"
            }
        }

        var tint: Color {
            switch self {
            case .welcome: .purple
            case .screenAccess: .blue
            case .openAtLogin: .teal
            case .ready: .green
            }
        }
    }

    static let stepKey = "onboardingStep"

    let model: AppModel
    let onFinish: () -> Void
    let onTour: () -> Void

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
                title: "Hi! Let's learn how you work",
                message: "Screen Journal quietly takes a snapshot of your screen every few seconds, but only when something changed. Everything stays on this Mac. After a week or two, Claude can read it and suggest ways to automate the boring parts.",
                action: ("Get Started", { advance(to: .screenAccess) })
            )
        case .screenAccess:
            ScreenAccessStep { advance(to: .openAtLogin) }
        case .openAtLogin:
            OpenAtLoginStep { advance(to: .ready) }
        case .ready:
            StepCard(
                title: "You're all set",
                message: "Look for the little aperture in your menu bar. Pause any time, or use Note This Moment when something feels tedious. If you ever wonder how something works, open How Screen Journal Works from that menu.",
                action: ("Start Journaling", {
                    model.markOnboarded()
                    onFinish()
                }),
                secondary: ("Show Me Around First", {
                    model.markOnboarded()
                    onTour()
                })
            )
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
    var secondary: (label: String, run: () -> Void)?

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
            if let secondary {
                Button(secondary.label, action: secondary.run).buttonStyle(.link)
            }
        }
    }
}

/// Polls the grant once a second; offers a relaunch because macOS often applies it only to a new process.
private struct ScreenAccessStep: View {
    let onGranted: () -> Void
    @State private var granted = SystemAccess.hasScreenAccess
    @State private var asked = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Allow screen snapshots").font(.title2.weight(.semibold))
            Text("macOS will ask you to turn on Screen Journal under **Screen & System Audio Recording**. Flip the switch, then come back here.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if granted {
                GrantedBadge(text: "Access granted")
            } else {
                Button(asked ? "Open System Settings Again" : "Open System Settings") {
                    asked = true
                    SystemAccess.requestScreenAccess()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 10)

                if asked {
                    Button("Already switched it on? Restart Screen Journal") { SystemAccess.relaunch() }
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

private struct OpenAtLoginStep: View {
    let onDone: () -> Void
    @State private var enabled = false
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 14) {
            Text("Always there when you log in").font(.title2.weight(.semibold))
            Text("Screen Journal starts by itself after a restart, so the week doesn't have holes. You can still pause it from the menu bar whenever you like.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if enabled {
                GrantedBadge(text: "Opens at login")
            } else if let failure {
                Text(failure).font(.callout).foregroundStyle(.orange)
                Button("Continue Anyway", action: onDone).controlSize(.large)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            do {
                try SystemAccess.enableOpenAtLogin()
                withAnimation(.spring(duration: 0.5, bounce: 0.4)) { enabled = true }
                try? await Task.sleep(for: .seconds(1.2))
                onDone()
            } catch {
                failure = "macOS didn't let us add the login item. Move the app to Applications and try again."
            }
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
