import AppFoundation

#if canImport(SwiftUI)
import SwiftUI

/// The piece an integrator copies first: `ScreenContainer` bound to `NotesViewModel`, a
/// list, and `send(.add(text))`. Never references `NotesLogic`/`NotesStore`/SwiftData
/// (`ARQUITECTURA-KIT-2026-09-02.md` §1, rule 4).
public struct NotesView: View {
    // The composition root builds the view model; the view RETAINS it (`@State`), so the
    // instance that receives `.load` is the one that stays on screen even if SwiftUI
    // re-runs this initializer during a push (PRD-X-05 A3).
    @State private var viewModel: NotesViewModel
    @State private var draftText = ""

    public init(viewModel: NotesViewModel) {
        _viewModel = State(initialValue: viewModel)
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
            .task {
                send(.load)
            }
        }
        .navigationTitle("Notes")
    }
}
#endif
