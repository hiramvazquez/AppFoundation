import Testing
@testable import AppFoundation

@Suite("ViewPhase & ScreenError")
struct ViewPhaseTests {
    // MARK: - Equality semantics (retry is deliberately ignored)

    @Test func errorPhasesWithDifferentRetryClosuresAreEqual() {
        let error1 = ScreenError(title: "Error", message: "Test", retry: {})
        let error2 = ScreenError(title: "Error", message: "Test", retry: {})
        #expect(ViewPhase.error(error1) == ViewPhase.error(error2))
    }

    @Test func errorPhasesWithAndWithoutRetryAreEqual() {
        let error1 = ScreenError(title: "Error", message: "Test")
        let error2 = ScreenError(title: "Error", message: "Test", retry: {})
        #expect(ViewPhase.error(error1) == ViewPhase.error(error2))
    }

    @Test func screenErrorsDifferingInTitleAreNotEqual() {
        let error1 = ScreenError(title: "Error 1", message: "Test error")
        let error2 = ScreenError(title: "Error 2", message: "Test error")
        #expect(error1 != error2)
    }

    @Test func screenErrorsDifferingInMessageAreNotEqual() {
        let error1 = ScreenError(title: "Error", message: "Test error 1")
        let error2 = ScreenError(title: "Error", message: "Test error 2")
        #expect(error1 != error2)
    }

    @Test func distinctPhasesAreNotEqual() {
        let phases: [ViewPhase] = [.idle, .loading, .content, .empty, .error(ScreenError(title: "E", message: "M"))]
        for (i, lhs) in phases.enumerated() {
            for (j, rhs) in phases.enumerated() where i != j {
                #expect(lhs != rhs)
            }
        }
    }

    // MARK: - ScreenError retry action

    @Test func screenErrorWithoutRetryHasNilRetry() {
        let error = ScreenError(title: "Error", message: "No retry")
        #expect(error.retry == nil)
    }

    @Test func screenErrorRetryExecutesTheAction() {
        var retryWasCalled = false
        let error = ScreenError(title: "Error", message: "With retry", retry: { retryWasCalled = true })
        error.retry?()
        #expect(retryWasCalled)
    }
}
