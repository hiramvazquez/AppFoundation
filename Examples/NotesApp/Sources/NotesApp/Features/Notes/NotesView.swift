import AppFoundation

#if canImport(SwiftUI)
import SwiftUI

/// The piece an integrator copies first: `ScreenContainer` bound to `NotesViewModel`, a
/// list, and `send(.add(text))`. Never references `NotesLogic`/`NotesStore`/SwiftData
/// (`ARQUITECTURA-KIT-2026-09-02.md` §1, rule 4).
public struct NotesView: View {
    let viewModel: NotesViewModel
    @State private var draftText = ""

    public init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScreenContainer(viewModel) { send in
            VStack(spacing: 0) {
                List {
                    ForEach(viewModel.notes) { note in
                        Text(note.text)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            send(.delete(viewModel.notes[index].id))
                        }
                    }
                }

                HStack {
                    TextField("New note", text: $draftText)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        send(.add(draftText))
                        draftText = ""
                    }
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .onAppear {
                send(.load)
            }
        }
        .navigationTitle("Notes")
    }
}
#endif
