import AppFoundationTestSupport
import Foundation

@testable import NotesApp

/// `NotesStoring` backed by `AppFoundationTestSupport.InMemoryStore` — what `NotesLogicTests`
/// runs against instead of a real `SwiftDataNotesStore`/`ModelContainer`: fast, and with no
/// shared on-disk state between tests.
///
/// `actor` (M5, same reasoning as `SwiftDataNotesStore`/`LoginApp`'s `SessionStoreSpy`): a
/// `Storing` conformance is `Sendable`, and an actor is the straightforward way to hold
/// mutable stubbed state behind that requirement.
actor InMemoryNotesStore: NotesStoring {
    private let storage = InMemoryStore<UUID, Note>()

    /// When set, `fetchAll`/`save`/`delete` throw this instead of touching `storage` — how
    /// `NotesLogicTests` exercises the `.storageFailure` mapping (M1).
    private var failureToThrow: (any Error)?

    init(failureToThrow: (any Error)? = nil) {
        self.failureToThrow = failureToThrow
    }

    func fetchAll() async throws -> [Note] {
        if let failureToThrow { throw failureToThrow }
        return await storage.values()
    }

    func save(_ note: Note) async throws {
        if let failureToThrow { throw failureToThrow }
        await storage.set(note.id, note)
    }

    func delete(_ id: UUID) async throws {
        if let failureToThrow { throw failureToThrow }
        await storage.remove(id)
    }
}
