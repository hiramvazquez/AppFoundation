import Testing

@testable import CounterApp

@Suite("CounterViewModel")
@MainActor
struct CounterViewModelTests {
    @Test("handle(.increment) calls logic.increment(count) and stores the result")
    func incrementCallsLogic() {
        let mock = CounterLogicMock()
        mock.nextValue = 7
        let viewModel = CounterViewModel(logic: mock)

        viewModel.handle(.increment)

        #expect(mock.incrementCalls == [0])
        #expect(viewModel.count == 7)
    }

    @Test("handle(.decrement) calls logic.decrement(count) and stores the result")
    func decrementCallsLogic() {
        let mock = CounterLogicMock()
        mock.nextValue = -1
        let viewModel = CounterViewModel(logic: mock)

        viewModel.handle(.decrement)

        #expect(mock.decrementCalls == [0])
        #expect(viewModel.count == -1)
    }

    @Test("handle(.reset) calls logic.reset() and stores the result")
    func resetCallsLogic() {
        let mock = CounterLogicMock()
        let viewModel = CounterViewModel(logic: mock)

        viewModel.handle(.reset)

        #expect(mock.resetCallCount == 1)
        #expect(viewModel.count == 0)
    }
}
