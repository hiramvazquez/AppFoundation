// Paso 4 de la guía «una app en 20 minutos»: Logic + LogicViewModel.
// `GreetingLogic` es la regla de negocio (aquí, una sola línea); el ViewModel
// solo orquesta: recibe la acción, llama a `logic`, actualiza el estado de pantalla.
import AppFoundation
import Observation

protocol GreetingLogicProtocol: Logic {
    func greeting(for name: String) -> String
}

final class GreetingLogic: GreetingLogicProtocol {
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

let viewModel = GreetingViewModel(logic: GreetingLogic())
viewModel.handle(.load(name: "Hiram"))
