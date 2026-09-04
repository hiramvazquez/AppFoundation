// Debouncer para un campo de búsqueda: solo la última pulsación dentro de la
// ventana dispara `search`. `@MainActor`, sin Task ni await en el call site.
import AppFoundation
import Observation

@Observable
final class SearchViewModel: BaseViewModel {
    // Nonisolated on purpose: without an explicit deinit the compiler synthesizes an isolated
    // one that goes through a back-deploy shim on older OS versions (see AppFoundation's
    // `docs/repros/isolated-deinit-backdeploy.md`). Nothing to clean up here.
    deinit {}

    private let debouncer = Debouncer(delay: .milliseconds(300))
    private(set) var query = ""

    func onQueryChanged(_ text: String) {
        query = text
        debouncer.debounce { [weak self] in
            self?.search()
        }
    }

    private func search() {
        performActivity { _ in
            // await apiService.search(query)
        }
    }
}
