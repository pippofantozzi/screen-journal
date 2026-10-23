import JournalCore
import SwiftUI

extension EnvironmentValues {
    @Entry var language: Language = .default
}

/// Wraps each window's root: every view below reads the chosen language, and switching it redraws them at once.
struct Localized<Content: View>: View {
    @AppStorage(Preferences.language) private var language = Language.default
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.language, language)
            .environment(\.locale, language.locale)
    }
}

extension Text {
    /// For translated phrases with **bold**, which a plain string wouldn't render.
    init(markdown: String) {
        self.init(LocalizedStringKey(markdown))
    }
}
