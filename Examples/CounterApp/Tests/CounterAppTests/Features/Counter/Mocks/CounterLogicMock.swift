import Foundation

@testable import CounterApp

/// Spy standing in for `CounterLogicProtocol` in `CounterViewModelTests` — the view model
/// under test never touches a real `CounterLogic`. Plain stored properties (no
/// `SpyRecorder`/actor): `CounterLogicProtocol`'s methods are synchronous — recording
/// into an `actor` from a sync call site would need an unstructured `Task`, which is
/// exactly the non-deterministic pattern this repo's tests avoid.
final class CounterLogicMock: CounterLogicProtocol {
    private(set) var incrementCalls: [Int] = []
    private(set) var decrementCalls: [Int] = []
    private(set) var resetCallCount = 0
    var nextValue = 0

    func increment(_ value: Int) -> Int {
        incrementCalls.append(value)
        return nextValue
    }

    func decrement(_ value: Int) -> Int {
        decrementCalls.append(value)
        return nextValue
    }

    func reset() -> Int {
        resetCallCount += 1
        return nextValue
    }
}
