import AppFoundation

/// Every operation `CounterViewModel` can ask its `Logic` for. `Logic`-conforming
/// (`ARQUITECTURA-KIT-2026-09-02.md` §1-2): a `ViewModel` depends on this protocol
/// through `init`, never on the concrete `CounterLogic` class.
public protocol CounterLogicProtocol: Logic {
    func increment(_ value: Int) -> Int
    func decrement(_ value: Int) -> Int
    func reset() -> Int
}

/// The "sin datos" variant (`ARQUITECTURA-KIT-2026-09-02.md` §1, tabla de variantes):
/// `Logic` depends on nothing — no `*Servicing`, no `*Storing` — just pure computation. It
/// still exists as its own type, exactly like every other variant's `Logic`, because
/// business rules belong there and nowhere else: today it's `value + 1`, tomorrow it might
/// be "never go below zero" or "increment by the step configured in Settings" — a rule
/// this simple already earns its own type, testable with zero collaborators, none of which
/// belongs in `CounterViewModel`.
///
/// `nonisolated` (M5): a `Logic` is not tied to the main actor. This one doesn't even need
/// `async` — pure computation has nothing to `await`.
public nonisolated final class CounterLogic: CounterLogicProtocol {
    public init() {}

    public func increment(_ value: Int) -> Int { value + 1 }
    public func decrement(_ value: Int) -> Int { value - 1 }
    public func reset() -> Int { 0 }
}
