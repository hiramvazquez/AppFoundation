import AppFoundation
import Observation
import Testing

// PRD-AF-11 A0 — `@Observable` is NOT inherited: the macro instruments only the stored
// properties declared in the class it is attached to. A `BaseViewModel` subclass that adds
// its own state must declare `@Observable` itself, or its properties never notify SwiftUI.

@MainActor
private final class PlainSubclass: BaseViewModel {
    var value = 0
}

@Observable
@MainActor
private final class MarkedSubclass: BaseViewModel {
    var value = 0
}

/// `withObservationTracking`'s `onChange` is `@Sendable`; a tiny box keeps the flag mutable there.
nonisolated private final class Flag: @unchecked Sendable {
    nonisolated(unsafe) var fired = false
}

@Suite("@Observable inheritance")
@MainActor
struct ObservationInheritanceTests {
    @Test("A subclass WITHOUT @Observable does not notify changes to its own properties")
    func plainSubclassIsNotObserved() {
        let viewModel = PlainSubclass()
        let flag = Flag()
        withObservationTracking {
            _ = viewModel.value
        } onChange: {
            flag.fired = true
        }
        viewModel.value = 1
        #expect(flag.fired == false, "If this fires, Observation started propagating to subclasses: revisit A0")
    }

    @Test("The same subclass WITH @Observable notifies, and the inherited phase keeps notifying too")
    func markedSubclassIsObserved() {
        let viewModel = MarkedSubclass()
        let own = Flag()
        withObservationTracking {
            _ = viewModel.value
        } onChange: {
            own.fired = true
        }
        viewModel.value = 1
        #expect(own.fired == true)

        let phase = Flag()
        withObservationTracking {
            _ = viewModel.phase
        } onChange: {
            phase.fired = true
        }
        viewModel.setContent()
        #expect(phase.fired == true)
    }
}
