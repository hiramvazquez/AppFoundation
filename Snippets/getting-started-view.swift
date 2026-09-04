// Paso 5 de la guía «una app en 20 minutos»: `ScreenContainer` renderiza fases
// (`.loading`/`.content`/`.error`) automáticamente. La vista nunca llama métodos
// del view model directamente, solo `send(.acción)`.
import AppFoundation
import SwiftUI

protocol GreetingLogicProtocol: Logic {
    func greeting(for name: String) -> String
}

nonisolated final class GreetingLogic: GreetingLogicProtocol {
    func greeting(for name: String) -> String {
        "Hola, \(name)"
    }
}

@Observable
final class GreetingViewModel: LogicViewModel<any GreetingLogicProtocol>, ActionHandling {
    // Nonisolated on purpose: without an explicit deinit the compiler synthesizes an isolated
    // one that goes through a back-deploy shim on older OS versions (see AppFoundation's
    // `docs/repros/isolated-deinit-backdeploy.md`). Nothing to clean up here.
    deinit {}

    private(set) var message: String = ""

    enum Action: Sendable {
        case load(name: String)
    }

    func handle(_ action: Action) {
        switch action {
        case .load(let name): load(name: name)
        }
    }

    private func load(name: String) {
        performLoad { vm in
            vm.message = vm.logic.greeting(for: name)
        }
    }
}

struct GreetingView: View {
    // El composition root construye el view model; la vista lo RETIENE con `@State`
    // (con `let`, SwiftUI puede sustituir la instancia que recibió `.load` al reejecutar
    // este init durante un push, y la que queda en pantalla nunca carga).
    @State private var viewModel: GreetingViewModel

    init(viewModel: GreetingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScreenContainer(viewModel) { send in
            Text(viewModel.message)
                .task { send(.load(name: "Hiram")) }
        }
        .navigationTitle("Saludo")
    }
}
