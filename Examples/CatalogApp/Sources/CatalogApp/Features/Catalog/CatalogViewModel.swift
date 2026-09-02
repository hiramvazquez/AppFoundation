import AppFoundation
import Foundation

/// Orchestrates between `CatalogView` and `CatalogLogic`, sequencing the cache-then-network
/// policy (`ARQUITECTURA-KIT-2026-09-02.md` §8, M7) over `logic.cached()`/`logic.refresh()`:
/// show whatever is cached immediately, then refresh from the network. A refresh failure
/// with cached items visible is a banner (content stays); a refresh failure with nothing
/// cached is the screen's error phase. Never imports the networking or persistence
/// frameworks — only `logic`.
@MainActor
public final class CatalogViewModel: LogicViewModel<any CatalogLogicProtocol>, ActionHandling {
    public private(set) var items: [Item] = []

    /// Every action `CatalogView` recognizes.
    public enum Action: Sendable {
        case load
    }

    public func handle(_ action: Action) {
        switch action {
        case .load: load()
        }
    }

    private func load() {
        performLoad(successTransition: .preserveCurrentPhase) { vm in
            let cached = await vm.logic.cached()
            if !cached.isEmpty {
                vm.items = cached
                vm.setContent()
            }

            do {
                let fresh = try await vm.logic.refresh()
                vm.items = fresh
                vm.setContent()
            } catch {
                // No cache to fall back on: this IS the screen's failure — let performLoad's
                // own catch turn it into the error phase.
                guard !cached.isEmpty else { throw error }
                // Cache exists: the refresh failing doesn't take the content away, it's a
                // banner (M7).
                vm.handleActivityError(error, strategy: .banner)
            }
        }
    }
}
