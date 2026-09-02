import Foundation
import Testing

@testable import NotesApp

/// `NotesLogic` tested purely against `InMemoryNotesStore` — no SwiftData, no
/// `ModelContainer`, no `ViewModel`.
@Suite("NotesLogic")
struct NotesLogicTests {
    @Test("addNote(text:) with only whitespace throws NotesError.emptyText before touching the store")
    func blankTextNeverReachesTheStore() async {
        let store = InMemoryNotesStore()
        let logic = NotesLogic(notesStore: store)

        await #expect(throws: NotesError.emptyText) {
            _ = try await logic.addNote(text: "   \n")
        }
        let stored = try? await store.fetchAll()
        #expect(stored?.isEmpty == true)
    }

    @Test("addNote(text:) trims and persists valid text")
    func addNoteTrimsAndPersists() async throws {
        let store = InMemoryNotesStore()
        let logic = NotesLogic(notesStore: store)

        let note = try await logic.addNote(text: "  Buy milk  ")

        #expect(note.text == "Buy milk")
        let stored = try await store.fetchAll()
        #expect(stored == [note])
    }

    @Test("loadNotes() returns what the store has")
    func loadNotesReturnsStoredNotes() async throws {
        let store = InMemoryNotesStore()
        let logic = NotesLogic(notesStore: store)
        _ = try await logic.addNote(text: "First")
        _ = try await logic.addNote(text: "Second")

        let notes = try await logic.loadNotes()

        #expect(notes.count == 2)
    }

    @Test("deleteNote(id:) removes the note from the store")
    func deleteNoteRemovesFromStore() async throws {
        let store = InMemoryNotesStore()
        let logic = NotesLogic(notesStore: store)
        let note = try await logic.addNote(text: "To delete")

        try await logic.deleteNote(id: note.id)

        let stored = try await store.fetchAll()
        #expect(stored.isEmpty)
    }

    @Test("A store failure maps to NotesError.storageFailure")
    func storeFailureMapsToDomainError() async {
        struct SomeStorageError: Error {}
        let store = InMemoryNotesStore(failureToThrow: SomeStorageError())
        let logic = NotesLogic(notesStore: store)

        await #expect(throws: NotesError.storageFailure) {
            _ = try await logic.addNote(text: "Anything")
        }
    }
}
