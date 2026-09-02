// Debouncer para un campo de búsqueda: solo la última pulsación dentro de la
// ventana dispara `search`. `@MainActor`, sin Task ni await en el call site.
import AppFoundation

final class SearchViewModel: BaseViewModel {
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
