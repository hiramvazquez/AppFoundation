// Un BaseViewModel mínimo: `performLoad` reemplaza el trabajo async, `phase`
// pasa por `.loading` → `.content`/`.error` sin código de estado escrito a mano.
import AppFoundation

struct Profile {
    let name: String
}

final class ProfileViewModel: BaseViewModel, ActionHandling {
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
