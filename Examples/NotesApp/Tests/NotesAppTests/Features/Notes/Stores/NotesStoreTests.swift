import Foundation
import SwiftData
import Testing

@testable import NotesApp

/// `SwiftDataNotesStore` tested against a REAL `ModelContainer` — in-memory only
/// (`isStoredInMemoryOnly: true`), never a mock of SwiftData itself.
@Suite("SwiftDataNotesStore")
struct NotesStoreTests {
    private func makeStore() throws -> SwiftDataNotesStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: NoteRecord.self, configurations: configuration)
        return SwiftDataNotesStore(modelContainer: container)
    }

    @Test("save(_:) then fetchAll() round-trips a Note")
    func saveThenFetchAllRoundTrips() async throws {
        let store = try makeStore()
        let note = Note(text: "Round trip")

        try await store.save(note)
        let fetched = try await store.fetchAll()

        #expect(fetched == [note])
    }

    @Test("fetchAll() returns notes newest-first")
    func fetchAllOrdersNewestFirst() async throws {
        let store = try makeStore()
        let older = Note(text: "Older", createdAt: Date(timeIntervalSince1970: 0))
        let newer = Note(text: "Newer", createdAt: Date(timeIntervalSince1970: 1000))

        try await store.save(older)
        try await store.save(newer)
        let fetched = try await store.fetchAll()

        #expect(fetched == [newer, older])
    }

    @Test("delete(_:) removes the note")
    func deleteRemovesNote() async throws {
        let store = try makeStore()
        let note = Note(text: "To delete")
        try await store.save(note)

        try await store.delete(note.id)

        let fetched = try await store.fetchAll()
        #expect(fetched.isEmpty)
    }

    @Test("delete(_:) for an id that doesn't exist is a no-op")
    func deleteUnknownIDIsNoOp() async throws {
        let store = try makeStore()

        try await store.delete(UUID())

        let fetched = try await store.fetchAll()
        #expect(fetched.isEmpty)
    }
}
