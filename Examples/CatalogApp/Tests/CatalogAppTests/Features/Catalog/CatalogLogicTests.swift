import CoreNetworking
import Foundation
import Testing

@testable import CatalogApp

/// `CatalogLogic` tested against `CatalogServiceMock`/`InMemoryCatalogStore` — no
/// `APIService`, no SwiftData, no `ViewModel`.
@Suite("CatalogLogic")
struct CatalogLogicTests {
    @Test("cached() returns what the store has")
    func cachedReturnsStoredItems() async throws {
        let store = InMemoryCatalogStore()
        let existingItem = Item(title: "Existing")
        try await store.replaceAll([existingItem])
        let logic = CatalogLogic(catalogService: CatalogServiceMock(), catalogStore: store)

        let cached = await logic.cached()

        #expect(cached == [existingItem])
    }

    @Test("cached() never throws — a store failure returns an empty list")
    func cachedNeverThrows() async {
        struct SomeStorageError: Error {}
        let store = InMemoryCatalogStore(fetchFailure: SomeStorageError())
        let logic = CatalogLogic(catalogService: CatalogServiceMock(), catalogStore: store)

        let cached = await logic.cached()

        #expect(cached.isEmpty)
    }

    @Test("refresh() fetches from the service, persists, and returns the fresh items")
    func refreshFetchesPersistsAndReturns() async throws {
        let freshItems = [Item(title: "Fresh 1"), Item(title: "Fresh 2")]
        let service = CatalogServiceMock(result: .success(freshItems))
        let store = InMemoryCatalogStore()
        let logic = CatalogLogic(catalogService: service, catalogStore: store)

        let items = try await logic.refresh()

        #expect(items == freshItems)
        #expect(await service.fetchCalls.count == 1)
        #expect(await store.replaceAllCalls.calls == [freshItems])
    }

    @Test("An offline service failure maps to CatalogError.offline")
    func offlineFailureMapsToDomainError() async {
        let service = CatalogServiceMock(
            result: .failure(.stub(code: .transport, underlying: URLError(.notConnectedToInternet)))
        )
        let logic = CatalogLogic(catalogService: service, catalogStore: InMemoryCatalogStore())

        await #expect(throws: CatalogError.offline) {
            _ = try await logic.refresh()
        }
    }

    @Test("A 5xx service failure maps to CatalogError.server")
    func serverFailureMapsToDomainError() async {
        let service = CatalogServiceMock(result: .failure(.stub(code: .httpStatus, statusCode: 503)))
        let logic = CatalogLogic(catalogService: service, catalogStore: InMemoryCatalogStore())

        await #expect(throws: CatalogError.server) {
            _ = try await logic.refresh()
        }
    }
}
