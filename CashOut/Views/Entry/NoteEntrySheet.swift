import SwiftUI

struct NoteEntrySheet: View {
    @Binding var noteText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Add a note", text: $noteText, axis: .vertical)
                    .lineLimit(3...6)
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NoteEntrySheet(noteText: .constant(""))
}
