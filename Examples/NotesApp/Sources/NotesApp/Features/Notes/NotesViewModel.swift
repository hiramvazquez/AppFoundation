import AppFoundation
import Foundation

/// Orchestrates between `NotesView` and `NotesLogic`: receives an `Action`, calls `logic`,
/// updates `notes`. Never imports the persistence framework, never references the
/// concrete store type directly (`ARQUITECTURA-KIT-2026-09-02.md` §1, rule 1) — only
/// `logic`.
@MainActor
public final class NotesViewModel: LogicViewModel<any NotesLogicProtocol>, ActionHandling {
    public private(set) var notes: [Note] = []

    /// Every action `NotesView` recognizes.
    public enum Action: Sendable {
        case load
        case add(String)
        case delete(UUID)
    }

    public func handle(_ action: Action) {
        switch action {
        case .load: load()
        case .add(let text): add(text)
        case .delete(let id): delete(id)
        }
    }

    private func load() {
        performLoad(successTransition: .preserveCurrentPhase) { vm in
            let notes = try await vm.logic.loadNotes()
            vm.notes = notes
            if notes.isEmpty { vm.setEmpty() } else { vm.setContent() }
        }
    }

    private func add(_ text: String) {
        performActivity { vm in
            let note = try await vm.logic.addNote(text: text)
            vm.notes.insert(note, at: 0)
            vm.setContent()
        }
    }

    private func delete(_ id: UUID) {
        performActivity { vm in
            try await vm.logic.deleteNote(id: id)
            vm.notes.removeAll { $0.id == id }
            if vm.notes.isEmpty { vm.setEmpty() }
        }
    }
}
