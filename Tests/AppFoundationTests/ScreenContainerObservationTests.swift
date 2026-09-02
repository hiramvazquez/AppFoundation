#if canImport(SwiftUI)
import Observation
import Testing

@testable import AppFoundation

// MARK: - DC-AF-4: `ObservingScreenState` tracks its wrapped view model without needing
// `@Observable` to do any work of its own — see the doc comment on the type for why.

@Suite("ObservingScreenState — observation without @Observable (DC-AF-4)")
struct ScreenContainerObservationTests {
    /// Reads `observingState.phase` the same way `ScreenContainer.body` does, then proves
    /// a change on the *wrapped* view model — never on `observingState` itself, which owns
    /// no storage of its own — is what fires `withObservationTracking`'s `onChange`.
    ///
    /// `onChange` runs on an arbitrary (non-`MainActor`, `@Sendable`) execution context —
    /// waiting on a `CheckedContinuation` is the deterministic way to await it, no polling.
    @MainActor
    @Test func changingTheWrappedViewModelFiresObservationTracking() async {
        let vm = BaseViewModel()
        let observingState = ObservingScreenState(vm)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                _ = observingState.phase
            } onChange: {
                continuation.resume()
            }
            vm.setContent()
        }
    }
}
#endif
