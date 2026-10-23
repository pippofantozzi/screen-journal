import AppKit
import JournalCore
import SwiftUI

/// What a week's sorted sessions looked like, filtered by task and by whether Claude could take them over.
struct ScreensView: View {
    let report: WeekReport
    let store: JournalStore
    @Binding var filter: Filter
    let back: () -> Void
    @Environment(\.language) private var language

    struct Filter: Equatable {
        /// nil for every task.
        var task: String?
        var share: WeekReport.Share = .any
    }

    var body: some View {
        let screens = report.screens(task: filter.task, share: filter.share)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Button(action: back) { Label(language("Your Week"), systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text(language("%@ sessions · %@", "\(screens.count)", Hours.text(screens.reduce(0) { $0 + $1.session.duration }, in: language)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            filters
            if screens.isEmpty {
                Text(language("Nothing here with these filters.")).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], alignment: .leading, spacing: 18) {
                        ForEach(screens, id: \.session.start) { screen in
                            ScreenCard(screen: screen, image: store.screenshot(of: screen.session))
                        }
                    }
                }
            }
        }
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Picker(language("Task"), selection: $filter.task) {
                Text(language("All tasks")).tag(String?.none)
                Divider()
                ForEach(report.tasks, id: \.task) { Text(language.name(ofKind: $0.task).capitalized(with: language.locale)).tag(Optional($0.task)) }
            }
            .labelsHidden()
            .fixedSize()
            Picker(language("Show"), selection: $filter.share) {
                Text(language("All")).tag(WeekReport.Share.any)
                Text(language("Claude could take over")).tag(WeekReport.Share.likely)
                Text(language("The rest")).tag(WeekReport.Share.rest)
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// One session: its screenshot, where it was, when, and how much of it Claude could take over.
private struct ScreenCard: View {
    let screen: WeekReport.Screen
    let image: URL
    @Environment(\.language) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Thumbnail(url: image)
            Text(place).lineLimit(1).truncationMode(.middle)
            Text(details).font(.callout).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var place: String {
        let app = screen.session.app ?? "?"
        guard let window = screen.session.windowTitle, !window.isEmpty else { return app }
        return "\(app) — \(window)"
    }

    private var details: String {
        let when = screen.session.start.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(language.locale))
        let parts = [when, Hours.text(screen.session.duration, in: language), language.name(ofKind: screen.label.task)]
        let share = Int((screen.helpShare * 100).rounded())
        return (parts + (share >= 5 ? ["~\(share)%"] : [])).joined(separator: " · ")
    }
}

/// Decoded small and off the main thread when it scrolls into view, and let go when it scrolls out.
private struct Thumbnail: View {
    let url: URL
    @State private var image: CGImage?
    @State private var missing = false
    @Environment(\.language) private var language

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.quaternary)
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else if missing {
                    Text(language("No screenshot kept")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { if image != nil { NSWorkspace.shared.open(url) } }
            .help(image != nil ? language("Open it larger") : "")
            .task(id: url) {
                let url = url
                image = await Task.detached(priority: .userInitiated) { ImageCodec.preview(at: url, maxPixelSize: 480) }.value
                missing = image == nil
            }
            .onDisappear { image = nil }
    }
}
