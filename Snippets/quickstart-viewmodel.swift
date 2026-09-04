// Un BaseViewModel mínimo: `performLoad` reemplaza el trabajo async, `phase`
// pasa por `.loading` → `.content`/`.error` sin código de estado escrito a mano.
import AppFoundation
import Observation

struct Profile {
    let name: String
}

@Observable
final class ProfileViewModel: BaseViewModel, ActionHandling {
    // Nonisolated on purpose: without an explicit deinit the compiler synthesizes an isolated
    // one that goes through a back-deploy shim on older OS versions (see AppFoundation's
    // `docs/repros/isolated-deinit-backdeploy.md`). Nothing to clean up here.
    deinit {}

    private(set) var profile: Profile?

    enum Action: Sendable {
        case load
    }

    func handle(_ action: Action) {
        switch action {
        case .load: load()
        }
    }

    private func load() {
        performLoad { vm in
            vm.profile = Profile(name: "Hiram")
        }
    }
}

let viewModel = ProfileViewModel()
viewModel.handle(.load)
