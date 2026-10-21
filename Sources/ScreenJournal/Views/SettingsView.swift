import JournalCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let model: AppModel
    @AppStorage(Preferences.interval) private var interval = 10.0
    @AppStorage(Preferences.retentionDays) private var retentionDays = 30
    @State private var excluded = UserDefaults.standard.stringArray(forKey: Preferences.excludedApps) ?? []
    @State private var choosingApp = false
    @State private var advice: IntervalAdvice?

    var body: some View {
        Form {
            Section("Capture") {
                Picker("Every", selection: $interval) {
                    ForEach(Preferences.intervalOptions, id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                }
                if let advice {
                    IntervalAdviceRow(advice: advice) { interval = $0 }
                }
                Stepper("Keep the last \(retentionDays) days", value: $retentionDays, in: 3...180, step: 1)
            }

            Section {
                ForEach(excluded.filter(isInstalled), id: \.self) { id in
                    HStack {
                        Text(appName(id))
                        Spacer()
                        Button(role: .destructive) { save(excluded.filter { $0 != id }) } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                Button("Add App…") { choosingApp = true }
            } header: {
                Text("Never capture")
            } footer: {
                Text("These apps are blanked out of screenshots, and nothing is saved while one is in front.")
            }

            Section("Journal") {
                LabeledContent("Folder", value: model.store.root.path(percentEncoded: false))
                Button("Open in Finder") { model.openFolder() }
            }
        }
        .formStyle(.grouped)
        .onChange(of: interval) { model.intervalDidChange() }
        .task(id: interval) { advice = await model.intervalAdvice() }
        .fileImporter(isPresented: $choosingApp, allowedContentTypes: [.application]) { result in
            if let id = (try? result.get()).flatMap({ Bundle(url: $0)?.bundleIdentifier }), !excluded.contains(id) {
                save(excluded + [id])
            }
        }
    }

    private func save(_ ids: [String]) {
        excluded = ids
        UserDefaults.standard.set(ids, forKey: Preferences.excludedApps)
    }

    private func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    private func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID
    }
}

/// One quiet line under the interval picker: still learning, all good, or a gentler interval worth trying.
private struct IntervalAdviceRow: View {
    let advice: IntervalAdvice
    let use: (TimeInterval) -> Void

    var body: some View {
        switch advice {
        case .learning(let have, let need):
            Text("Learning your rhythm · suggestion after ~\(duration(need)) of use (\(duration(have)) so far)")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .keep(let interval):
            Text("✓ Every \(Int(interval)) seconds suits how you work")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .suggest(let interval, let visits, let text, let savedWork):
            HStack {
                Text("Every \(Int(interval)) seconds would still catch \(percent(min(visits, text))) of what you do, with \(percent(savedWork)) less work")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Use \(Int(interval)) seconds") { use(interval) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .abbreviated
        f.zeroFormattingBehavior = .dropAll
        return f.string(from: seconds) ?? ""
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded(.down)))%"
    }
}
