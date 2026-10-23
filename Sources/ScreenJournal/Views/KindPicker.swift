import JournalCore
import SwiftUI

/// Her kinds of task: click a suggestion to add it, or type her own and press Return.
/// Click one of her own to edit it; every pick's × removes it, a suggestion going back among the suggestions.
struct KindPicker: View {
    @Binding var picked: [String]
    let suggestions: [Suggestion]
    @State private var draft = ""
    /// The pick being edited; Return puts it back in the same place.
    @State private var editing: Int?
    /// The pick she just tried to add again, lit up for a moment.
    @State private var echoed: String?
    /// The suggestion under the pointer; the input line says what it covers, at once.
    @State private var pointed: String?
    @Environment(\.language) private var language

    /// A suggested kind: `id` is what the journal stores, `name` what she reads, `meaning` what it covers.
    struct Suggestion {
        let id: String
        let name: String
        let meaning: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if picked.isEmpty {
                Text(language("None picked yet, so every suggestion is used."))
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(Array(picked.enumerated()), id: \.offset) { index, kind in
                        chip(kind, at: index)
                    }
                }
            }
            ZStack(alignment: .topLeading) {
                TextField("", text: $draft, prompt: Text(editing == nil ? language("Add your own, then press Return") : language("Edit, then press Return")))
                    .labelsHidden()
                    .onSubmit(commit)
                    .onExitCommand(perform: cancel)
                    .opacity(meaning == nil ? 1 : 0)
                if let meaning {
                    Text(meaning)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !unpicked.isEmpty {
                Text(language("Suggestions: click to add"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                FlowLayout(spacing: 6) {
                    ForEach(unpicked, id: \.id) { suggestionChip($0) }
                }
            }
        }
    }

    private var unpicked: [Suggestion] {
        suggestions.filter { LabelSetup.included($0.id, in: picked) == nil }
    }

    /// What the pointed kind covers, in place of the empty input line; wraps, unlike a placeholder.
    private var meaning: String? {
        guard draft.isEmpty, editing == nil, let tag = suggestions.first(where: { $0.id == pointed }) else { return nil }
        return "\(tag.name): \(tag.meaning)"
    }

    private func chip(_ kind: String, at index: Int) -> some View {
        let suggestion = suggestions.first { $0.id.caseInsensitiveCompare(kind) == .orderedSame }
        return HStack(spacing: 4) {
            if let suggestion {
                Text(suggestion.name)
            } else {
                Button(kind) { edit(index) }
                    .buttonStyle(.plain)
            }
            Button { remove(index) } label: {
                Image(systemName: "xmark").font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(language("Delete %@", suggestion?.name ?? kind))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(editing == index || echoed == kind ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.18)))
        .modifier(Pointing(id: suggestion?.id, pointed: $pointed))
        .help(suggestion?.meaning ?? "")
    }

    private func suggestionChip(_ suggestion: Suggestion) -> some View {
        Button { add(suggestion.id) } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus").font(.caption2.weight(.semibold))
                Text(suggestion.name)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().strokeBorder(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(Pointing(id: suggestion.id, pointed: $pointed))
        .help(suggestion.meaning)
        .accessibilityLabel(language("Add %@", suggestion.name))
    }

    private func add(_ id: String) {
        withAnimation { picked = LabelSetup.adding(id, to: picked) }
        if pointed == id { pointed = nil }
    }

    /// A repeat, even of the pick being edited into another one, lights up the one already there and changes nothing.
    /// A suggestion typed by its name in her language, ignoring case and accents, adds it: "Conteudo" is "content".
    private func commit() {
        var others = picked
        if let editing { others.remove(at: editing) }
        let name = suggestionMatch(draft) ?? draft
        if let match = LabelSetup.included(name, in: others) { return echo(match) }
        let added = LabelSetup.adding(name, to: others)
        if let editing, added.count > others.count { others.insert(added.last!, at: editing) }
        picked = editing == nil ? added : others
        draft = ""
        editing = nil
    }

    private func suggestionMatch(_ draft: String) -> String? {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return suggestions.first { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }?.id
    }

    private func echo(_ kind: String) {
        draft = ""
        editing = nil
        withAnimation { echoed = kind }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation { if echoed == kind { echoed = nil } }
        }
    }

    private func edit(_ index: Int) {
        editing = index
        draft = picked[index]
    }

    private func cancel() {
        draft = ""
        editing = nil
    }

    private func remove(_ index: Int) {
        if editing == index { cancel() }
        else if let editing, editing > index { self.editing = editing - 1 }
        if pointed == picked[index] { pointed = nil }
        withAnimation { _ = picked.remove(at: index) }
    }
}

/// Tracks which kind is under the pointer, by id; nil ids are her own kinds, which mean what they say.
private struct Pointing: ViewModifier {
    let id: String?
    @Binding var pointed: String?

    func body(content: Content) -> some View {
        content.onHover { inside in
            guard let id else { return }
            if inside { pointed = id } else if pointed == id { pointed = nil }
        }
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        var y: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
