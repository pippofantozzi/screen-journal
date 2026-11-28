import JournalCore
import SwiftUI

/// One window, a pane per thing she might come to change: the journal, keeping awake, dictation, and what they share.
struct SettingsView: View {
    let model: AppModel
    let dictation: DictationController
    let awake: AwakeController
    let noteShortcutWorks: Bool
    let showGuide: () -> Void
    @State private var pane = Pane.journal
    @Environment(\.language) private var language

    enum Pane: CaseIterable {
        case journal, awake, dictation, general

        var title: String {
            switch self {
            case .journal: "Journal"
            case .awake: "Keep Awake"
            case .dictation: "Dictation"
            case .general: "General"
            }
        }

        var symbol: String {
            switch self {
            case .journal: "camera.aperture"
            case .awake: "eye"
            case .dictation: "mic"
            case .general: "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, id: \.self, selection: $pane) { pane in
                Label(language(pane.title), systemImage: pane.symbol)
            }
            .navigationSplitViewColumnWidth(160)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch pane {
            case .journal: JournalSettings(model: model, noteShortcutWorks: noteShortcutWorks)
            case .awake: AwakeSettings(awake: awake)
            case .dictation: DictationSettings(dictation: dictation)
            case .general: GeneralSettings(model: model, showGuide: showGuide)
            }
        }
    }
}
