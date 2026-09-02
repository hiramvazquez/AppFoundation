// `inFlightLoad`/`inFlightActivity` evitan sondear `phase` en un bucle: el test
// espera el `Task` que `performLoad`/`handle(_:)` ya está corriendo.
import AppFoundation

final class CounterViewModel: BaseViewModel, ActionHandling {
    private(set) var count = 0

    enum Action: Sendable {
        case increment
    }

    func handle(_ action: Action) {
        switch action {
        case .increment: increment()
        }
    }

    private func increment() {
        performLoad { vm in
            vm.count += 1
        }
    }
}

@MainActor
func incrementAndWait() async {
    let viewModel = CounterViewModel()
    viewModel.handle(.increment)
    await viewModel.inFlightLoad?.value
    assert(viewModel.phase == .content)
    assert(viewModel.count == 1)
}

await incrementAndWait()
