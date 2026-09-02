import Foundation

@testable import CatalogApp

/// Spy standing in for `CatalogLogicProtocol` in `CatalogViewModelTests` — used to test
/// `CatalogViewModel`'s cache-then-network POLICY (M7) in isolation, independent of what
/// `CatalogLogic` itself does with `CatalogServicing`/`CatalogStoring`.
final class CatalogLogicMock: CatalogLogicProtocol {
    private(set) var cachedCallCount = 0
    private(set) var refreshCallCount = 0

    var cachedToReturn: [Item] = []
    var refreshResult: Result<[Item], any Error> = .success([])

    func cached() async -> [Item] {
        cachedCallCount += 1
        return cachedToReturn
    }

    func refresh() async throws -> [Item] {
        refreshCallCount += 1
        return try refreshResult.get()
    }
}
