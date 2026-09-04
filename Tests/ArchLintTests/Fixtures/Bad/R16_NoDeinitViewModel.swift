import AppFoundation

// R16: a MainActor class without an explicit deinit gets a synthesized isolated one.
@Observable
final class R16NoDeinitViewModel: BaseViewModel, ActionHandling {
    var items: [String] = []
    enum Action: Sendable { case load }
    func handle(_ action: Action) {}
}
