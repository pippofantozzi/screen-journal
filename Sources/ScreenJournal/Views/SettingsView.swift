import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let model: AppModel
    @AppStorage(Preferences.interval) private var interval = 10.0
    @AppStorage(Preferences.retentionDays) private var retentionDays = 30
    @State private var excluded = UserDefaults.standard.stringArray(forKey: Preferences.excludedApps) ?? []
    @State private var choosingApp = false

    var body: some View {
        Form {
            Section("Capture") {
                Picker("Every", selection: $interval) {
                    ForEach([5.0, 10, 15, 30, 60], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
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
