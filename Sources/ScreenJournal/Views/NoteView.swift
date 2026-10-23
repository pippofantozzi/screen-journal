import JournalCore
import SwiftUI

/// A one-line note that lands in the journal with a timestamp.
/// The highest-signal input Claude gets: "this part is tedious".
struct NoteView: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.language) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language("What's going on right now?"))
                .font(.headline)
            TextField(language("e.g. copying invoices into the spreadsheet again"), text: $text, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { onSave(text) }
            HStack {
                Spacer()
                Button(language("Cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(language("Save Note")) { onSave(text) }
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
