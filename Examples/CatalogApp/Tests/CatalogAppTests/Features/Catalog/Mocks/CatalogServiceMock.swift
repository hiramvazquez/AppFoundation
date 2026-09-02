import AppFoundationTestSupport
import CoreNetworking
import Foundation

@testable import CatalogApp

/// Spy standing in for `CatalogServicing` in `CatalogLogicTests` — `CatalogLogic` under
/// test never touches `APIServiceProtocol`/a real network pipeline.
///
/// `actor` (M5, same reasoning as `LoginApp`'s `LoginServiceMock`): `Servicing` is
/// `Sendable`.
actor CatalogServiceMock: CatalogServicing {
    let fetchCalls = SpyRecorder<Void>()
    private var result: Result<[Item], APIError>

    init(result: Result<[Item], APIError> = .success([])) {
        self.result = result
    }

    func fetchItems() async throws(APIError) -> [Item] {
        await fetchCalls.record()
        switch result {
        case .success(let items): return items
        case .failure(let error): throw error
        }
    }
}

/// `CatalogStoring` backed by `AppFoundationTestSupport.InMemoryStore` — what
/// `CatalogLogicTests` runs against instead of a real `SwiftDataCatalogStore`.
actor InMemoryCatalogStore: CatalogStoring {
    private let storage = InMemoryStore<UUID, Item>()
    let replaceAllCalls = SpyRecorder<[Item]>()

    /// When set, `fetchAll` throws this instead of touching `storage` — how
    /// `CatalogLogicTests` exercises `cached()`'s "never throws, returns []" contract.
    private var fetchFailure: (any Error)?

    init(fetchFailure: (any Error)? = nil) {
        self.fetchFailure = fetchFailure
    }

    func fetchAll() async throws -> [Item] {
        if let fetchFailure { throw fetchFailure }
        return await storage.values()
    }

    func replaceAll(_ items: [Item]) async throws {
        await replaceAllCalls.record(items)
        await storage.removeAll()
        for item in items {
            await storage.set(item.id, item)
        }
    }
}
