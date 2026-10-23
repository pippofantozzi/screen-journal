import SwiftUI

/// A one-line note that lands in the journal with a timestamp.
/// The highest-signal input Claude gets: "this part is tedious".
struct NoteView: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What's going on right now?")
                .font(.headline)
            TextField("e.g. copying invoices into the spreadsheet again", text: $text, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { onSave(text) }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save Note") { onSave(text) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        // The panel turns key a moment after the view appears; focusing on appear alone is lost.
        .defaultFocus($focused, true)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}
