import Foundation
import SwiftData

// MARK: - The persistence model (M2: only this file ever sees it)

/// The SwiftData entity. Never leaves this file: `SwiftDataCatalogStore` maps it to `Item`
/// (the domain model) on the way out, and back on the way in.
@Model
final class ItemRecord {
    // Explicit, nonisolated deinit (linter rule R16): avoids the synthesized isolated deinit
    // and its back-deploy shim on older OS versions. Nothing to clean up.
    deinit {}

    @Attribute(.unique) var id: UUID
    var title: String

    init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }
}

// MARK: - The store

/// The local cache `CatalogLogic.cached()`/`refresh()` reads and writes.
/// `CatalogLogic` depends on this protocol through `init` — never on
/// `SwiftDataCatalogStore` directly (`ARQUITECTURA-KIT-2026-09-02.md` §1, rule 3).
public protocol CatalogStoring: Sendable {
    func fetchAll() async throws -> [Item]

    /// Replaces the ENTIRE cache with `items` — the catalog is a full snapshot from the
    /// server on every refresh, not a diff.
    func replaceAll(_ items: [Item]) async throws
}

/// The `CatalogStoring` this app runs with. `@ModelActor` (M5, same reasoning as
/// `NotesApp`'s `SwiftDataNotesStore`): SwiftData's `ModelContext` is not `Sendable` and
/// its initializer is main-actor-isolated.
@ModelActor
public actor SwiftDataCatalogStore: CatalogStoring {
    public func fetchAll() async throws -> [Item] {
        let descriptor = FetchDescriptor<ItemRecord>(sortBy: [SortDescriptor(\.title)])
        let records = try modelContext.fetch(descriptor)
        return records.map { Item(id: $0.id, title: $0.title) }
    }

    public func replaceAll(_ items: [Item]) async throws {
        let existing = try modelContext.fetch(FetchDescriptor<ItemRecord>())
        for record in existing {
            modelContext.delete(record)
        }
        for item in items {
            modelContext.insert(ItemRecord(id: item.id, title: item.title))
        }
        try modelContext.save()
    }
}
