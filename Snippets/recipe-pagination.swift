// Paginación: la carga inicial usa `performLoad`; cargar la página siguiente es
// `activity` — no reemplaza el contenido ya visible mientras llega más.
import AppFoundation
import Observation

struct Page: Sendable {
    let items: [String]
    let hasMore: Bool
}

protocol FeedLoading: Sendable {
    func load(page: Int) async throws -> Page
}

@Observable
final class FeedViewModel: BaseViewModel, ActionHandling {
    // Nonisolated on purpose: without an explicit deinit the compiler synthesizes an isolated
    // one that goes through a back-deploy shim on older OS versions (see AppFoundation's
    // `docs/repros/isolated-deinit-backdeploy.md`). Nothing to clean up here.
    deinit {}

    private(set) var items: [String] = []
    private var currentPage = 0
    private var hasMore = true
    private let service: any FeedLoading

    enum Action: Sendable {
        case load
        case loadNextPage
    }

    init(service: any FeedLoading) {
        self.service = service
    }

    func handle(_ action: Action) {
        switch action {
        case .load: load()
        case .loadNextPage: loadNextPage()
        }
    }

    private func load() {
        performLoad { vm in
            let page = try await vm.service.load(page: 0)
            vm.items = page.items
            vm.hasMore = page.hasMore
            vm.currentPage = 0
        }
    }

    private func loadNextPage() {
        guard hasMore else { return }
        performActivity(style: .inline) { vm in
            let page = try await vm.service.load(page: vm.currentPage + 1)
            vm.items += page.items
            vm.hasMore = page.hasMore
            vm.currentPage += 1
        }
    }
}
