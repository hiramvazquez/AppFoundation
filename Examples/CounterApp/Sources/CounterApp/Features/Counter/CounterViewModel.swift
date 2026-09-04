import AppFoundation
import Observation

/// Orchestrates between `CounterView` and `CounterLogic`: receives an `Action`, calls
/// `logic`, updates `count`. Never contains a rule itself — "what happens on increment" is
/// `CounterLogic`'s job, not this type's.
@MainActor
@Observable
public final class CounterViewModel: LogicViewModel<any CounterLogicProtocol>, ActionHandling {
    public private(set) var count = 0

    /// Every action `CounterView` recognizes.
    public enum Action: Sendable {
        case increment
        case decrement
        case reset
    }

    public func handle(_ action: Action) {
        switch action {
        case .increment: count = logic.increment(count)
        case .decrement: count = logic.decrement(count)
        case .reset: count = logic.reset()
        }
    }
}
