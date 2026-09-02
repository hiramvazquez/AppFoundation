import AppFoundation
import Foundation

@MainActor
public final class LoginViewModel: LogicViewModel<any LoginLogicProtocol>, ActionHandling {
    public private(set) var items: [LoginItem] = []

    public enum Action: Sendable {
        case load
    }

    public func handle(_ action: Action) {
        switch action {
        case .load: load()
        }
    }

    private func load() {
        performLoad { vm in
            let items = try await vm.logic.load()
            vm.items = items
            items.isEmpty ? vm.setEmpty() : vm.setContent()
        }
    }
}
