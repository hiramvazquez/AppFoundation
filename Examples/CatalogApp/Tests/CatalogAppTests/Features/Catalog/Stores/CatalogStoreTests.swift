import Foundation
import SwiftData
import Testing

@testable import CatalogApp

/// `SwiftDataCatalogStore` tested against a REAL `ModelContainer` — in-memory only.
@Suite("SwiftDataCatalogStore")
struct CatalogStoreTests {
    private func makeStore() throws -> SwiftDataCatalogStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ItemRecord.self, configurations: configuration)
        return SwiftDataCatalogStore(modelContainer: container)
    }

    @Test("replaceAll(_:) then fetchAll() round-trips the items")
    func replaceAllThenFetchAllRoundTrips() async throws {
        let store = try makeStore()
        let items = [Item(title: "Alpha"), Item(title: "Beta")]

        try await store.replaceAll(items)
        let fetched = try await store.fetchAll()

        #expect(Set(fetched) == Set(items))
    }

    @Test("replaceAll(_:) discards whatever was cached before — a full snapshot, not a merge")
    func replaceAllDiscardsPreviousItems() async throws {
        let store = try makeStore()
        try await store.replaceAll([Item(title: "Old")])

        let newItem = Item(title: "New")
        try await store.replaceAll([newItem])
        let fetched = try await store.fetchAll()

        #expect(fetched == [newItem])
    }

    @Test("fetchAll() on an empty store returns an empty list")
    func fetchAllOnEmptyStoreReturnsEmpty() async throws {
        let store = try makeStore()

        let fetched = try await store.fetchAll()

        #expect(fetched.isEmpty)
    }
}
