import JournalCore
import SwiftUI

/// Where her week went by kind of task, how much of it Claude could probably take over,
/// and the windows to start with. Read-only: it shows the answers already in the journal.
struct WeekView: View {
    let store: JournalStore
    @State private var lastDay: String
    @State private var phase: Phase = .loading
    private let today: String

    enum Phase {
        case loading
        case loaded(WeekReport)
        case failed(String)
    }

    init(store: JournalStore) {
        self.store = store
        today = store.day(of: Date())
        _lastDay = State(initialValue: today)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            switch phase {
            case .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message): Text(message).foregroundStyle(.secondary)
            case .loaded(let report): content(report)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: lastDay) { await load() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            if case .loaded(let report) = phase {
                Text(report.tracked > 0 ? "\(Hours.text(report.tracked)) tracked" : "Nothing tracked")
                    .font(.title2.weight(.semibold))
            }
            Spacer()
            Button { step(-7) } label: { Image(systemName: "chevron.left") }
                .help("The week before")
            Text(range).monospacedDigit().foregroundStyle(.secondary)
            Button { step(7) } label: { Image(systemName: "chevron.right") }
                .disabled(lastDay >= today)
                .help("The week after")
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder private func content(_ report: WeekReport) -> some View {
        if report.tasks.isEmpty {
            Text(report.tracked > 0
                ? "Nothing sorted yet this week. Once your sessions are sorted, you'll see here where your time went."
                : "Screen Journal wasn't recording these days.")
                .foregroundStyle(.secondary)
        } else {
            TaskBars(tasks: report.tasks)
            if !report.candidates.isEmpty { suggestions(report.candidates) }
        }
        if report.unsorted >= 60, !report.tasks.isEmpty {
            Text("Not sorted yet: \(Hours.text(report.unsorted)). It shows up here once it's sorted.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func suggestions(_ candidates: [Labeling.Candidate]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where Claude could help most").font(.headline)
            ForEach(Array(candidates.enumerated()), id: \.offset) { index, c in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1).").foregroundStyle(.secondary).monospacedDigit()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.window.isEmpty ? c.app : "\(c.app) — \(c.window)").lineLimit(1).truncationMode(.middle)
                        Text("\(Hours.text(c.seconds)) · \(c.task)").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var range: String {
        let days = WeekReport.days(endingOn: lastDay)
        guard let first = Hours.date(days.first ?? lastDay), let last = Hours.date(lastDay) else { return lastDay }
        return (first..<last.addingTimeInterval(1)).formatted(.interval.month(.abbreviated).day())
    }

    private func step(_ days: Int) {
        guard let date = Hours.date(lastDay) else { return }
        lastDay = min(today, store.day(of: date.addingTimeInterval(Double(days) * 86_400 + 43_200)))
    }

    private func load() async {
        let store = store, day = lastDay
        let result = await Task.detached { store.weekReport(endingOn: day) }.value
        switch result {
        case .success(let report): phase = .loaded(report)
        case .failure(let error): phase = .failed(error.message)
        }
    }
}

/// One bar per task, as long as its time; the dark part is the share Claude could probably take over.
private struct TaskBars: View {
    let tasks: [Labeling.TaskTime]

    var body: some View {
        let longest = tasks.map(\.seconds).max() ?? 1
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(tasks, id: \.task) { task in
                    GridRow {
                        Text(task.task.capitalized)
                        bar(task, of: longest)
                        Text(Hours.text(task.seconds)).monospacedDigit().gridColumnAlignment(.trailing)
                        Text(task.helpShare >= 0.05 ? "~\(Int((task.helpShare * 100).rounded()))%" : "")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
            legend
        }
    }

    private func bar(_ task: Labeling.TaskTime, of longest: TimeInterval) -> some View {
        GeometryReader { geo in
            let total = geo.size.width * task.seconds / longest
            let help = total * task.helpShare
            HStack(spacing: help >= 1 && total - help >= 1 ? 2 : 0) {
                if help >= 1 { UnevenRoundedRectangle(cornerRadii: .init(topLeading: 4, bottomLeading: 4)).fill(Color.accentColor).frame(width: help) }
                if total - help >= 1 { UnevenRoundedRectangle(cornerRadii: .init(bottomTrailing: 4, topTrailing: 4)).fill(Color.accentColor.opacity(0.3)) }
            }
            .frame(width: max(total, 2), alignment: .leading)
        }
        .frame(height: 12)
        .help("\(task.task.capitalized): \(Hours.text(task.seconds)), of which Claude could probably take over \(Hours.text(task.handoff))")
    }

    private var legend: some View {
        HStack(spacing: 14) {
            swatch(Color.accentColor, "Claude could probably take over")
            swatch(Color.accentColor.opacity(0.3), "The rest")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label)
        }
    }
}

/// Durations and day names the way she reads them.
private enum Hours {
    static func text(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2))
    }

    static func date(_ day: String) -> Date? {
        try? Date("\(day)T12:00:00", strategy: Date.ISO8601FormatStyle(timeZone: .current).year().month().day().time(includingFractionalSeconds: false).dateTimeSeparator(.standard))
    }
}
