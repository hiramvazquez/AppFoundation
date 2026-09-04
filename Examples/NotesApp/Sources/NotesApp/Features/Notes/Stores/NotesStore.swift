import Foundation
import SwiftData

// MARK: - The persistence model (M2: only this file ever sees it)

/// The SwiftData entity. Never leaves this file: `SwiftDataNotesStore` maps it to `Note`
/// (the domain model `NotesLogic`/`NotesViewModel` work with) on the way out, and back on
/// the way in — the same DTO/domain split `LoginApp`'s `LoginRequest.Response`/`Session`
/// makes for a network response.
@Model
final class NoteRecord {
    // Explicit, nonisolated deinit (linter rule R16): avoids the synthesized isolated deinit
    // and its back-deploy shim on older OS versions. Nothing to clean up.
    deinit {}

    @Attribute(.unique) var id: UUID
    var text: String
    var createdAt: Date

    init(id: UUID, text: String, createdAt: Date) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

// MARK: - The store

/// Local persistence for notes. `NotesLogic` depends on this protocol through `init` —
/// never on `SwiftDataNotesStore` directly (`ARQUITECTURA-KIT-2026-09-02.md` §1, rule 3).
public protocol NotesStoring: Sendable {
    func fetchAll() async throws -> [Note]
    func save(_ note: Note) async throws
    func delete(_ id: UUID) async throws
}

/// The `NotesStoring` this app runs with. `@ModelActor` (M5: "actor (o `@ModelActor` con
/// SwiftData)"): SwiftData's `ModelContext` is not `Sendable` and its own initializer is
/// `@MainActor`-isolated — a hand-written `actor` that builds a `ModelContext` itself in a
/// plain `init` cannot satisfy that from an arbitrary (non-main) isolation, which is
/// exactly the problem `@ModelActor` exists to solve: it generates the actor's isolated
/// `modelContext`/`modelExecutor` machinery and an `init(modelContainer:)` that constructs
/// it correctly. See `NotesModule.swift` for how a real app builds the `ModelContainer`
/// this takes.
@ModelActor
public actor SwiftDataNotesStore: NotesStoring {
    public func fetchAll() async throws -> [Note] {
        let descriptor = FetchDescriptor<NoteRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let records = try modelContext.fetch(descriptor)
        return records.map { Note(id: $0.id, text: $0.text, createdAt: $0.createdAt) }
    }

    public func save(_ note: Note) async throws {
        let record = NoteRecord(id: note.id, text: note.text, createdAt: note.createdAt)
        modelContext.insert(record)
        try modelContext.save()
    }

    public func delete(_ id: UUID) async throws {
        let descriptor = FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(record)
        try modelContext.save()
    }
}
