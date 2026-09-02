import Foundation
import Testing

@testable import AppFoundation

#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - AF-05: ScreenState, ActionHandling, ActionSender

/// A minimal `@Observable` view model that conforms to `ScreenViewModel`
/// (`ScreenState & ActionHandling`) WITHOUT inheriting from `BaseViewModel` — the whole
/// point of AF-05: `ScreenContainer` depends on the protocol, not the concrete class.
@Observable
@MainActor
private final class StandaloneCounterViewModel: ScreenState, ActionHandling {
    // MARK: ScreenState
    private(set) var phase: ViewPhase = .content
    private(set) var activity: ActivityState = .none
    var alert: AlertState?
    var banner: BannerState?

    // MARK: ActionHandling
    enum Action: Sendable {
        case increment
        case reset
    }

    private(set) var count = 0

    func handle(_ action: Action) {
        switch action {
        case .increment: count += 1
        case .reset: count = 0
        }
    }
}

/// A tiny `ActionHandling` conformer used purely to prove `ActionSender` forwards to
/// `handle(_:)` and does not retain its view model.
@MainActor
private final class RecordingHandler: ActionHandling {
    enum Action: Sendable, Equatable {
        case ping
        case pong(Int)
    }

    private(set) var received: [Action] = []

    func handle(_ action: Action) {
        received.append(action)
    }
}

@Suite("ActionHandling / ActionSender (AF-05)")
struct ActionHandlingTests {
    // MARK: - ActionSender forwards to handle(_:)

    @Test func senderForwardsEveryActionToHandle() {
        let handler = RecordingHandler()
        let sender = handler.sender

        sender(.ping)
        sender.send(.pong(42))

        #expect(handler.received == [.ping, .pong(42)])
    }

    /// `callAsFunction` and `send(_:)` are the same call spelled two ways.
    @Test func callAsFunctionAndSendAreEquivalent() {
        let handler = RecordingHandler()
        let sender = handler.sender

        sender(.ping)
        sender.send(.ping)

        #expect(handler.received == [.ping, .ping])
    }

    // MARK: - ActionSender does not retain its view model (weak var test)

    /// `ActionHandling.sender` is built with `[weak self]`: a view can hold on to the
    /// sender after the view model it points to has been deallocated — sending an action
    /// through it becomes a safe no-op instead of resurrecting/crashing (the same contract
    /// `BaseViewModelMemoryTests` verifies for `performLoad`'s retry action).
    @Test func senderDoesNotRetainItsViewModel() {
        weak var weakHandler: RecordingHandler?
        var capturedSender: ActionSender<RecordingHandler.Action>?

        _ = {
            let handler = RecordingHandler()
            weakHandler = handler
            capturedSender = handler.sender
        }()

        #expect(weakHandler == nil)

        // Sending through a sender whose view model is gone is a safe no-op.
        capturedSender?.send(.ping)
        #expect(weakHandler == nil)
    }

    // MARK: - ScreenContainer compiles against a standalone ScreenViewModel

    /// `ScreenContainer(_ state:chrome:content:)` requires `State: ScreenState &
    /// ActionHandling` (`ScreenViewModel`) — NOT the concrete `BaseViewModel` class. This
    /// is a real compile test: `StandaloneCounterViewModel` conforms to `ScreenViewModel`
    /// without inheriting from `BaseViewModel` at all, and `ScreenContainer` still accepts
    /// it, deriving its content closure's `ActionSender<StandaloneCounterViewModel.Action>`
    /// straight from the protocol.
    ///
    /// The negative half of this contract can't be expressed as a runtime test (Swift has
    /// no "assert this fails to compile"): the counterexample below is commented out
    /// because it genuinely does not compile — `PlainObservableWithNoActions` conforms to
    /// `ScreenState` but not `ActionHandling`, so `ScreenContainer(vm) { send in ... }`
    /// fails with "generic struct 'ScreenContainer' requires that
    /// 'PlainObservableWithNoActions' conform to 'ActionHandling'" (verified against this
    /// package's own `ScreenContainer.swift`; see `ScreenContainer(observing:)` for the
    /// initializer that's actually meant for a `ScreenState` with no actions).
    ///
    /// ```swift
    /// @Observable @MainActor
    /// final class PlainObservableWithNoActions: ScreenState {
    ///     var phase: ViewPhase = .content
    ///     var activity: ActivityState = .none
    ///     var alert: AlertState?
    ///     var banner: BannerState?
    /// }
    ///
    /// // Does NOT compile: PlainObservableWithNoActions has no `handle(_:)`.
    /// _ = ScreenContainer(PlainObservableWithNoActions()) { send in EmptyView() }
    /// ```
    @Test @MainActor func screenContainerCompilesAgainstAStandaloneScreenViewModel() {
        #if canImport(SwiftUI)
        let viewModel = StandaloneCounterViewModel()
        let container = ScreenContainer(viewModel) { send in
            Button("Increment") { send(.increment) }
        }
        _ = container
        #expect(viewModel.count == 0)  // building the view doesn't run the closure eagerly
        #endif
    }

    // MARK: - The content closure only ever sees an ActionSender, never the view model

    @Test @MainActor func handleReachesPrivateBehaviorWithoutExposingIt() {
        let viewModel = StandaloneCounterViewModel()

        // The same call a view's `send(.increment)` makes — no private method reached.
        viewModel.handle(.increment)
        viewModel.handle(.increment)
        viewModel.handle(.reset)
        viewModel.handle(.increment)

        #expect(viewModel.count == 1)
    }
}
