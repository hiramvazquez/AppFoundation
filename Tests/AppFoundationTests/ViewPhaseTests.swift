import XCTest
@testable import AppFoundation

@MainActor
final class ViewPhaseTests: XCTestCase {
    // MARK: - ViewPhase Equality Tests

    func testIdleEquality() {
        let phase1: ViewPhase = .idle
        let phase2: ViewPhase = .idle
        XCTAssertEqual(phase1, phase2)
    }

    func testLoadingEquality() {
        let phase1: ViewPhase = .loading
        let phase2: ViewPhase = .loading
        XCTAssertEqual(phase1, phase2)
    }

    func testContentEquality() {
        let phase1: ViewPhase = .content
        let phase2: ViewPhase = .content
        XCTAssertEqual(phase1, phase2)
    }

    func testEmptyEquality() {
        let phase1: ViewPhase = .empty
        let phase2: ViewPhase = .empty
        XCTAssertEqual(phase1, phase2)
    }

    func testErrorEquality() {
        let error = ScreenError(title: "Error", message: "Test error")
        let phase1: ViewPhase = .error(error)
        let phase2: ViewPhase = .error(error)
        XCTAssertEqual(phase1, phase2)
    }

    func testErrorEqualityIgnoresRetryAction() {
        // Errors should be equal regardless of retry action
        let error1 = ScreenError(title: "Error", message: "Test", retry: { print("retry1") })
        let error2 = ScreenError(title: "Error", message: "Test", retry: { print("retry2") })
        let phase1: ViewPhase = .error(error1)
        let phase2: ViewPhase = .error(error2)
        XCTAssertEqual(phase1, phase2)
    }

    func testErrorEqualityWithoutRetry() {
        let error1 = ScreenError(title: "Error", message: "Test")
        let error2 = ScreenError(title: "Error", message: "Test")
        let phase1: ViewPhase = .error(error1)
        let phase2: ViewPhase = .error(error2)
        XCTAssertEqual(phase1, phase2)
    }

    // MARK: - ViewPhase Pattern Matching Tests

    func testPatternMatchingIdle() {
        let phase: ViewPhase = .idle
        var matched = false
        if case .idle = phase {
            matched = true
        }
        XCTAssertTrue(matched)
    }

    func testPatternMatchingLoading() {
        let phase: ViewPhase = .loading
        var matched = false
        if case .loading = phase {
            matched = true
        }
        XCTAssertTrue(matched)
    }

    func testPatternMatchingContent() {
        let phase: ViewPhase = .content
        var matched = false
        if case .content = phase {
            matched = true
        }
        XCTAssertTrue(matched)
    }

    func testPatternMatchingEmpty() {
        let phase: ViewPhase = .empty
        var matched = false
        if case .empty = phase {
            matched = true
        }
        XCTAssertTrue(matched)
    }

    func testPatternMatchingError() {
        let error = ScreenError(title: "Error", message: "Test")
        let phase: ViewPhase = .error(error)
        var capturedError: ScreenError?
        if case .error(let e) = phase {
            capturedError = e
        }
        XCTAssertNotNil(capturedError)
        XCTAssertEqual(capturedError?.title, "Error")
        XCTAssertEqual(capturedError?.message, "Test")
    }

    // MARK: - ScreenError Tests

    func testScreenErrorEquality() {
        let error1 = ScreenError(title: "Error", message: "Test error")
        let error2 = ScreenError(title: "Error", message: "Test error")
        XCTAssertEqual(error1, error2)
    }

    func testScreenErrorInequality_DifferentTitle() {
        let error1 = ScreenError(title: "Error 1", message: "Test error")
        let error2 = ScreenError(title: "Error 2", message: "Test error")
        XCTAssertNotEqual(error1, error2)
    }

    func testScreenErrorInequality_DifferentMessage() {
        let error1 = ScreenError(title: "Error", message: "Test error 1")
        let error2 = ScreenError(title: "Error", message: "Test error 2")
        XCTAssertNotEqual(error1, error2)
    }

    func testScreenErrorWithoutRetry() {
        let error = ScreenError(title: "Error", message: "No retry")
        XCTAssertNil(error.retry)
    }

    func testScreenErrorWithRetry() {
        var retryWasCalled = false
        let error = ScreenError(
            title: "Error",
            message: "With retry",
            retry: { retryWasCalled = true }
        )
        XCTAssertNotNil(error.retry)
        error.retry?()
        XCTAssertTrue(retryWasCalled)
    }

    // MARK: - LoadingStyle Tests

    func testLoadingStyleFullScreen() {
        let style: LoadingStyle = .fullScreen
        var matched = false
        if case .fullScreen = style {
            matched = true
        }
        XCTAssertTrue(matched)
    }

    func testLoadingStyleInline() {
        let style: LoadingStyle = .inline
        var matched = false
        if case .inline = style {
            matched = true
        }
        XCTAssertTrue(matched)
    }

    func testLoadingStyleOverlay() {
        let style: LoadingStyle = .overlay
        var matched = false
        if case .overlay = style {
            matched = true
        }
        XCTAssertTrue(matched)
    }

    func testLoadingStyleEquality() {
        XCTAssertEqual(LoadingStyle.fullScreen, .fullScreen)
        XCTAssertEqual(LoadingStyle.inline, .inline)
        XCTAssertEqual(LoadingStyle.overlay, .overlay)
    }

    func testLoadingStyleInequality() {
        XCTAssertNotEqual(LoadingStyle.fullScreen, .inline)
        XCTAssertNotEqual(LoadingStyle.inline, .overlay)
        XCTAssertNotEqual(LoadingStyle.overlay, .fullScreen)
    }

    // MARK: - ViewPhase Switch Tests

    func testSwitchAllCases() {
        let phases: [ViewPhase] = [
            .idle,
            .loading,
            .content,
            .empty,
            .error(ScreenError(title: "E", message: "M"))
        ]

        for phase in phases {
            switch phase {
            case .idle, .loading, .content, .empty, .error:
                break
            }
        }
    }

    func testPhaseTransitionSequence() {
        var phase: ViewPhase = .idle
        XCTAssertEqual(phase, .idle)

        phase = .loading
        XCTAssertEqual(phase, .loading)

        phase = .content
        XCTAssertEqual(phase, .content)

        phase = .error(ScreenError(title: "E", message: "M"))
        if case .error = phase {
        } else {
            XCTFail("Expected error phase")
        }
    }
}
