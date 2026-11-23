import AppKit
import JournalCore
import SwiftUI

/// What a week's sorted sessions looked like, filtered by task, share, or a specific window,
/// with quick actions to correct a label, forget a session, or exclude its app.
struct ScreensView: View {
    let report: WeekReport
    let model: AppModel
    @Binding var filter: Filter
    let back: () -> Void
    @Environment(\.language) private var language

    struct Filter: Equatable {
        /// nil for every task.
        var task: String? = nil
        var share: WeekReport.Share = .any
        var app: String? = nil
        var window: String? = nil
    }

    private var kinds: [TaskKind] {
        (try? model.store.labelSetup().get().kinds) ?? (TaskKind.suggestions + [TaskKind.other])
    }

    var body: some View {
        let screens = report.screens(task: filter.task, share: filter.share, app: filter.app, window: filter.window)
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
                            ScreenCard(screen: screen, image: model.store.screenshot(of: screen.session), kinds: kinds, model: model)
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
            if let app = filter.app {
                let label = (filter.window?.isEmpty == false) ? "\(app) — \(filter.window!)" : app
                HStack(spacing: 4) {
                    Text(label).lineLimit(1).truncationMode(.middle)
                    Button {
                        filter.app = nil
                        filter.window = nil
                    } label: {
                        Image(systemName: "xmark").font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.18)))
            }
        }
    }
}

/// One session: its screenshot, where it was, when, and how much of it Claude could take over.
private struct ScreenCard: View {
    let screen: WeekReport.Screen
    let image: URL
    let kinds: [TaskKind]
    let model: AppModel
    @Environment(\.language) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Thumbnail(url: image)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(place).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Menu {
                    actions
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            Text(details).font(.callout).foregroundStyle(.secondary).lineLimit(1)
        }
        .contextMenu { actions }
    }

    @ViewBuilder private var actions: some View {
        Menu(language("Change Task")) {
            ForEach(kinds, id: \.name) { kind in
                Button {
                    Task {
                        await model.correctLabel(
                            session: screen.session,
                            work: kind.name == "leisure" ? 0 : max(screen.label.work, 0.9),
                            automatable: kind.name == "leisure" ? 0 : screen.label.automatable,
                            task: kind.name
                        )
                    }
                } label: {
                    if kind.name == screen.label.task {
                        Label(language.name(ofKind: kind.name).capitalized(with: language.locale), systemImage: "checkmark")
                    } else {
                        Text(language.name(ofKind: kind.name).capitalized(with: language.locale))
                    }
                }
            }
        }
        Button(language("Mark as Personal")) {
            Task {
                await model.correctLabel(session: screen.session, work: 0, automatable: 0, task: "leisure")
            }
        }
        Divider()
        if let bundleID = screen.session.bundleID, let app = screen.session.app {
            Button(language("Exclude %@", app)) {
                model.excludeApp(bundleID: bundleID)
            }
        }
        Button(language("Forget This Session"), role: .destructive) {
            Task {
                await model.forget(from: screen.session.start, to: screen.session.end.addingTimeInterval(1))
            }
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
