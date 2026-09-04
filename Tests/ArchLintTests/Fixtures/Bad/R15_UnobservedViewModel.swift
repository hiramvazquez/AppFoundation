import AppFoundation

// R15: a ViewModel subclass without @Observable never notifies its own properties.
final class R15UnobservedViewModel: BaseViewModel, ActionHandling {
    var items: [String] = []
    enum Action: Sendable { case load }
    func handle(_ action: Action) {}
}
