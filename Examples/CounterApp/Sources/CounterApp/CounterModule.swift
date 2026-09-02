import AppFoundation

/// Registers the Counter feature into a `Container`: the composition root is the only
/// place that knows the concrete `CounterLogic` behind `CounterLogicProtocol` (M4) — a
/// real app's root view resolves `CounterViewModel` from the container instead of
/// constructing it directly.
///
/// ```swift
/// Container.shared.register(modules: [CounterModule()])
/// // Root view:
/// CounterView(viewModel: Container.shared.resolve())
/// ```
public struct CounterModule: DependencyModule {
    public init() {}

    public func register(in container: Container) {
        container.register(CounterLogicProtocol.self) { _ in CounterLogic() }
        container.register(CounterViewModel.self, lifecycle: .transient) { c in
            CounterViewModel(logic: c.resolve())
        }
    }
}
