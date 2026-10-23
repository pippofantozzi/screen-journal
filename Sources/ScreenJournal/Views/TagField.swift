import JournalCore
import SwiftUI

/// Type a name and press Return to add it as a tag. Click a tag to edit it; its × deletes it.
/// The fixed tags come first and can't be changed; typing one of them lights it up instead.
struct TagField: View {
    @Binding var tags: [String]
    /// Name and what it means, shown on hover.
    let fixed: [(name: String, meaning: String)]
    let prompt: String
    @State private var draft = ""
    /// The tag being edited; Return puts it back in the same place.
    @State private var editing: Int?
    /// The tag she just tried to add again, lit up for a moment.
    @State private var echoed: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                ForEach(fixed, id: \.name) { fixedChip($0.name).help($0.meaning) }
                ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                    chip(tag, at: index)
                }
            }
            TextField("", text: $draft, prompt: Text(editing == nil ? prompt : "Edit, then press Return"))
                .labelsHidden()
                .onSubmit(commit)
                .onExitCommand(perform: cancel)
        }
    }

    private func chip(_ tag: String, at index: Int) -> some View {
        HStack(spacing: 4) {
            Button(tag) { edit(index) }
                .buttonStyle(.plain)
            Button { delete(index) } label: {
                Image(systemName: "xmark").font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Delete \(tag)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(editing == index || echoed == tag ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.18)))
    }

    private func fixedChip(_ tag: String) -> some View {
        Text(tag)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().strokeBorder(echoed == tag ? Color.accentColor : Color.secondary.opacity(0.3)))
            .background(Capsule().fill(echoed == tag ? Color.accentColor.opacity(0.2) : .clear))
    }

    /// A repeat, even of the tag being edited into another one, lights up the one already there and changes nothing.
    private func commit() {
        var others = tags
        if let editing { others.remove(at: editing) }
        if let match = LabelSetup.included(draft, in: others) { return echo(match) }
        let added = LabelSetup.adding(draft, to: others)
        if let editing, added.count > others.count { others.insert(added.last!, at: editing) }
        tags = editing == nil ? added : others
        draft = ""
        editing = nil
    }

    private func echo(_ tag: String) {
        draft = ""
        editing = nil
        withAnimation { echoed = tag }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation { if echoed == tag { echoed = nil } }
        }
    }

    private func edit(_ index: Int) {
        editing = index
        draft = tags[index]
    }

    private func cancel() {
        draft = ""
        editing = nil
    }

    private func delete(_ index: Int) {
        if editing == index { cancel() }
        else if let editing, editing > index { self.editing = editing - 1 }
        tags.remove(at: index)
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
