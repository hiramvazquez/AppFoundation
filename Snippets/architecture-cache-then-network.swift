// Variante "API + local" (M7): dos llamadas explícitas, `cached()` y `refresh()`,
// en vez de un AsyncStream — más simple de llamar y de testear.
//
// `CatalogLogicProtocol: Logic, Sendable` — un consumidor con
// `.enableUpcomingFeature("NonisolatedNonsendingByDefault")` (como este propio paquete,
// ver `AppFoundation/Package.swift`) no necesita el `Sendable` explícito: una `Logic`
// `nonisolated` corre en el actor del llamador. Se deja aquí para que el snippet compile
// igual sin esa feature activada.
import AppFoundation
import Observation

struct Item: Sendable, Equatable {
    let id: String
    let title: String
}

enum CatalogError: DomainError {
    case offline

    var screenError: ScreenError {
        ScreenError(title: "Sin conexión", message: "Mostrando la última copia guardada.")
    }
}

protocol CatalogServicing: Sendable {
    func fetchItems() async throws -> [Item]
}

protocol CatalogStoring: Sendable {
    func cachedItems() async -> [Item]
    func replaceAll(_ items: [Item]) async
}

protocol CatalogLogicProtocol: Logic, Sendable {
    func cached() async -> [Item]
    func refresh() async throws(CatalogError) -> [Item]
}

final class CatalogLogic: CatalogLogicProtocol {
    private let service: any CatalogServicing
    private let store: any CatalogStoring

    init(service: any CatalogServicing, store: any CatalogStoring) {
        self.service = service
        self.store = store
    }

    func cached() async -> [Item] {
        await store.cachedItems()
    }

    func refresh() async throws(CatalogError) -> [Item] {
        do {
            let items = try await service.fetchItems()
            await store.replaceAll(items)
            return items
        } catch {
            throw .offline
        }
    }
}

@Observable
final class CatalogViewModel: LogicViewModel<any CatalogLogicProtocol>, ActionHandling {
    private(set) var items: [Item] = []

    enum Action: Sendable { case load }

    func handle(_ action: Action) {
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
                vm.items = try await vm.logic.refresh()
                vm.setContent()
            } catch {
                // Sin caché que mostrar: es el fallo de la pantalla — deja que el
                // catch de performLoad lo convierta en fase de error.
                guard !cached.isEmpty else { throw error }
                // Hay caché: el fallo del refresh no se lleva el contenido, es un banner (M7).
                vm.handleActivityError(error, strategy: .banner)
            }
        }
    }
}
