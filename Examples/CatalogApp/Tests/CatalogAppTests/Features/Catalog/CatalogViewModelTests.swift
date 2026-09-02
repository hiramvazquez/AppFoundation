import Foundation
import Testing

@testable import CatalogApp

/// The cache-then-network POLICY (`ARQUITECTURA-KIT-2026-09-02.md` §8, M7), tested against
/// `CatalogLogicMock` — independent of `CatalogService`/`CatalogStore`.
@Suite("CatalogViewModel — cache-then-network policy")
@MainActor
struct CatalogViewModelTests {
    @Test("No cache, refresh succeeds: reaches .content with the fresh items")
    func noCacheRefreshSucceeds() async {
        let mock = CatalogLogicMock()
        let freshItem = Item(title: "Fresh")
        mock.cachedToReturn = []
        mock.refreshResult = .success([freshItem])
        let viewModel = CatalogViewModel(logic: mock)

        viewModel.handle(.load)
        await viewModel.inFlightLoad?.value

        #expect(viewModel.phase == .content)
        #expect(viewModel.items == [freshItem])
    }

    @Test("No cache, refresh fails: reaches the screen's error phase")
    func noCacheRefreshFails() async {
        let mock = CatalogLogicMock()
        mock.cachedToReturn = []
        mock.refreshResult = .failure(CatalogError.offline)
        let viewModel = CatalogViewModel(logic: mock)

        viewModel.handle(.load)
        await viewModel.inFlightLoad?.value

        #expect(viewModel.hasError)
        #expect(viewModel.items.isEmpty)
        #expect(viewModel.banner == nil)
    }

    @Test("Cache present, refresh succeeds: content is replaced by the fresh items")
    func cachePresentRefreshSucceeds() async {
        let mock = CatalogLogicMock()
        let cachedItem = Item(title: "Cached")
        let freshItem = Item(title: "Fresh")
        mock.cachedToReturn = [cachedItem]
        mock.refreshResult = .success([freshItem])
        let viewModel = CatalogViewModel(logic: mock)

        viewModel.handle(.load)
        await viewModel.inFlightLoad?.value

        #expect(viewModel.phase == .content)
        #expect(viewModel.items == [freshItem])
    }

    @Test("Cache present, refresh fails: a banner shows, content keeps the cached items")
    func cachePresentRefreshFailsShowsBanner() async {
        let mock = CatalogLogicMock()
        let cachedItem = Item(title: "Cached")
        mock.cachedToReturn = [cachedItem]
        mock.refreshResult = .failure(CatalogError.offline)
        let viewModel = CatalogViewModel(logic: mock)

        viewModel.handle(.load)
        await viewModel.inFlightLoad?.value

        #expect(viewModel.phase == .content)
        #expect(viewModel.items == [cachedItem])
        #expect(viewModel.banner != nil)
    }

    @Test("Both cached() and refresh() are called exactly once per load")
    func bothCallsHappenExactlyOnce() async {
        let mock = CatalogLogicMock()
        mock.cachedToReturn = [Item(title: "Cached")]
        mock.refreshResult = .success([Item(title: "Fresh")])
        let viewModel = CatalogViewModel(logic: mock)

        viewModel.handle(.load)
        await viewModel.inFlightLoad?.value

        #expect(mock.cachedCallCount == 1)
        #expect(mock.refreshCallCount == 1)
    }
}
