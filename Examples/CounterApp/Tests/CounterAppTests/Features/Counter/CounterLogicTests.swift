import Testing

@testable import CounterApp

@Suite("CounterLogic")
struct CounterLogicTests {
    @Test("increment adds one")
    func incrementAddsOne() {
        #expect(CounterLogic().increment(0) == 1)
        #expect(CounterLogic().increment(41) == 42)
    }

    @Test("decrement subtracts one")
    func decrementSubtractsOne() {
        #expect(CounterLogic().decrement(1) == 0)
        #expect(CounterLogic().decrement(0) == -1)
    }

    @Test("reset always returns zero")
    func resetReturnsZero() {
        #expect(CounterLogic().reset() == 0)
    }
}
