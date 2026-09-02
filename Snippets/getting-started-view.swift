// Paso 5 de la guía «una app en 20 minutos»: `ScreenContainer` renderiza fases
// (`.loading`/`.content`/`.error`) automáticamente. La vista nunca llama métodos
// del view model directamente, solo `send(.acción)`.
import AppFoundation
import SwiftUI

protocol GreetingLogicProtocol: Logic {
    func greeting(for name: String) -> String
}

final class GreetingLogic: GreetingLogicProtocol {
    func greeting(for name: String) -> String {
        "Hola, \(name)"
    }
}

final class GreetingViewModel: LogicViewModel<any GreetingLogicProtocol>, ActionHandling {
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
    let viewModel: GreetingViewModel

    var body: some View {
        ScreenContainer(viewModel) { send in
            Text(viewModel.message)
                .onAppear { send(.load(name: "Hiram")) }
        }
        .navigationTitle("Saludo")
    }
}
