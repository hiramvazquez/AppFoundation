import Testing

@testable import AppFoundation

// MARK: - PRD-AF-07: `LogicViewModel<L>`

private protocol CounterLogicProtocol: Logic {
    func increment(_ value: Int) async -> Int
}

/// Production conformance: pure computation, no dependencies (the "sin datos" variant).
private final class CounterLogic: CounterLogicProtocol {
    func increment(_ value: Int) async -> Int { value + 1 }
}

/// Test conformance (spy): records every call and lets the test control the result —
/// proves a `LogicViewModel` subclass is testable purely against the `*LogicProtocol`,
/// with no real `CounterLogic` involved.
private final class CounterLogicSpy: CounterLogicProtocol {
    private(set) var incrementCalls: [Int] = []
    var result = 0

    func increment(_ value: Int) async -> Int {
        incrementCalls.append(value)
        return result
    }
}

/// A minimal `ViewModel` built on `LogicViewModel<any CounterLogicProtocol>`: it only
/// orchestrates (`handle(_:)` calls `logic.increment` and updates `count`), it never
/// constructs `CounterLogic` itself, and `Action` is declared here, not on the base class
/// (`LogicViewModel` deliberately does not conform to `ActionHandling`).
@MainActor
private final class CounterViewModel: LogicViewModel<any CounterLogicProtocol>, ActionHandling {
    private(set) var count = 0

    enum Action: Sendable {
        case increment
    }

    func handle(_ action: Action) {
        switch action {
        case .increment: increment()
        }
    }

    private func increment() {
        performLoad(successTransition: .preserveCurrentPhase) { vm in
            vm.count = await vm.logic.increment(vm.count)
            vm.setContent()
        }
    }
}

@Suite("LogicViewModel<L> (PRD-AF-07)")
@MainActor
struct LogicViewModelTests {
    @Test("logic is stored and reachable from the subclass")
    func logicIsStored() {
        let logic = CounterLogic()
        let viewModel = CounterViewModel(logic: logic)

        #expect(ObjectIdentifier(viewModel.logic) == ObjectIdentifier(logic))
    }

    @Test("A LogicViewModel subclass inherits BaseViewModel/LoadableViewModel behavior")
    func inheritsBaseViewModelBehavior() async {
        let spy = CounterLogicSpy()
        spy.result = 42
        let viewModel = CounterViewModel(logic: spy)

        #expect(viewModel.isIdle)

        viewModel.handle(.increment)
        await viewModel.inFlightLoad?.value

        #expect(viewModel.phase == .content)
        #expect(viewModel.count == 42)
        #expect(spy.incrementCalls == [0])
    }

    @Test("A different Logic conformance (spy) is substitutable through the same init")
    func logicIsSubstitutableThroughInit() async {
        let productionViewModel = CounterViewModel(logic: CounterLogic())
        let spyViewModel = CounterViewModel(logic: CounterLogicSpy())

        productionViewModel.handle(.increment)
        await productionViewModel.inFlightLoad?.value
        spyViewModel.handle(.increment)
        await spyViewModel.inFlightLoad?.value

        // Same call sequence through the same base class, different Logic conformances,
        // different (independently correct) outcomes: `logic` is never hard-coded.
        #expect(productionViewModel.count == 1)
        #expect(spyViewModel.count == 0)
    }
}
