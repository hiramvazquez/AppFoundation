import XCTest
import Combine
@testable import AppFoundation

@MainActor
final class BaseViewModelTests: XCTestCase {
    var viewModel: BaseViewModel!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        viewModel = BaseViewModel()
        cancellables = []
    }

    override func tearDown() {
        viewModel = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialPhaseIsIdle() {
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func testInitialLoadingStyleIsFullScreen() {
        XCTAssertEqual(viewModel.loadingStyle, .fullScreen)
    }

    func testInitialAlertIsNil() {
        XCTAssertNil(viewModel.alert)
    }

    func testInitialBannerIsNil() {
        XCTAssertNil(viewModel.banner)
    }

    // MARK: - Phase Transition Tests

    func testSetLoading_DefaultStyle() {
        // When
        viewModel.setLoading()

        // Then
        XCTAssertEqual(viewModel.phase, .loading)
        XCTAssertEqual(viewModel.loadingStyle, .fullScreen)
    }

    func testSetLoading_InlineStyle() {
        // When
        viewModel.setLoading(.inline)

        // Then
        XCTAssertEqual(viewModel.phase, .loading)
        XCTAssertEqual(viewModel.loadingStyle, .inline)
    }

    func testSetLoading_OverlayStyle() {
        // When
        viewModel.setLoading(.overlay)

        // Then
        XCTAssertEqual(viewModel.phase, .loading)
        XCTAssertEqual(viewModel.loadingStyle, .overlay)
    }

    func testSetContent() {
        // When
        viewModel.setContent()

        // Then
        XCTAssertEqual(viewModel.phase, .content)
    }

    func testSetEmpty() {
        // When
        viewModel.setEmpty()

        // Then
        XCTAssertEqual(viewModel.phase, .empty)
    }

    func testSetError_WithScreenError() {
        // Given
        let error = ScreenError(title: "Test Error", message: "Something went wrong")

        // When
        viewModel.setError(error)

        // Then
        XCTAssertTrue(viewModel.hasError)
        XCTAssertEqual(viewModel.currentError, error)
    }

    func testSetError_WithTitleAndMessage() {
        // When
        viewModel.setError(title: "Network Error", message: "Failed to connect")

        // Then
        XCTAssertTrue(viewModel.hasError)
        XCTAssertEqual(viewModel.currentError?.title, "Network Error")
        XCTAssertEqual(viewModel.currentError?.message, "Failed to connect")
    }

    func testSetError_WithRetryAction() {
        // Given
        var retryWasCalled = false
        let retryAction: Action = { retryWasCalled = true }

        // When
        viewModel.setError(title: "Error", message: "Retry me", retry: retryAction)

        // Then
        XCTAssertTrue(viewModel.hasError)
        viewModel.currentError?.retry?()
        XCTAssertTrue(retryWasCalled)
    }

    func testSetIdle() {
        // Given
        viewModel.setContent()
        XCTAssertEqual(viewModel.phase, .content)

        // When
        viewModel.setIdle()

        // Then
        XCTAssertEqual(viewModel.phase, .idle)
    }

    // MARK: - Alert Tests

    func testShowAlert() {
        // Given
        let alert = AlertState.info(title: "Info", message: "This is info")

        // When
        viewModel.showAlert(alert)

        // Then
        XCTAssertNotNil(viewModel.alert)
        XCTAssertEqual(viewModel.alert?.title, "Info")
    }

    func testDismissAlert() {
        // Given
        let alert = AlertState.info(title: "Info", message: "This is info")
        viewModel.showAlert(alert)
        XCTAssertNotNil(viewModel.alert)

        // When
        viewModel.dismissAlert()

        // Then
        XCTAssertNil(viewModel.alert)
    }

    func testShowAlertConfirmation() {
        // Given
        var confirmWasCalled = false
        let alert = AlertState.confirmation(
            title: "Confirm?",
            message: "Are you sure?",
            confirm: "Yes",
            cancel: "No",
            onConfirm: { confirmWasCalled = true }
        )

        // When
        viewModel.showAlert(alert)
        viewModel.alert?.primaryButton.action()

        // Then
        XCTAssertTrue(confirmWasCalled)
    }

    func testShowAlertDestructive() {
        // Given
        var deleteWasCalled = false
        let alert = AlertState.destructive(
            title: "Delete?",
            message: "Cannot undo",
            confirm: "Delete",
            cancel: "Cancel",
            onConfirm: { deleteWasCalled = true }
        )

        // When
        viewModel.showAlert(alert)

        // Then
        XCTAssertEqual(viewModel.alert?.primaryButton.role, .destructive)
    }

    // MARK: - Banner Tests

    func testShowBanner() {
        // Given
        let banner = BannerState.success("Saved!")

        // When
        viewModel.showBanner(banner)

        // Then
        XCTAssertNotNil(viewModel.banner)
        XCTAssertEqual(viewModel.banner?.message, "Saved!")
        XCTAssertEqual(viewModel.banner?.style, .success)
    }

    func testShowBannerError() {
        // When
        viewModel.showBanner(BannerState.error("Failed!"))

        // Then
        XCTAssertEqual(viewModel.banner?.style, .error)
    }

    func testShowBannerInfo() {
        // When
        viewModel.showBanner(BannerState.info("Info"))

        // Then
        XCTAssertEqual(viewModel.banner?.style, .info)
    }

    func testShowBannerWarning() {
        // When
        viewModel.showBanner(BannerState.warning("Warning"))

        // Then
        XCTAssertEqual(viewModel.banner?.style, .warning)
    }

    func testDismissBanner() {
        // Given
        viewModel.showBanner(BannerState.success("Saved!"))
        XCTAssertNotNil(viewModel.banner)

        // When
        viewModel.dismissBanner()

        // Then
        XCTAssertNil(viewModel.banner)
    }

    // MARK: - Load Helper Tests

    func testLoadSuccess() {
        // Given
        let expectation = XCTestExpectation(description: "Load completes")
        var workWasExecuted = false

        // When
        viewModel.load {
            workWasExecuted = true
        }

        // Then - wait for async work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(workWasExecuted)
            XCTAssertEqual(self.viewModel.phase, .content)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testLoadFailure() {
        // Given
        let expectation = XCTestExpectation(description: "Load fails")

        // When
        viewModel.load {
            throw NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        }

        // Then
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.viewModel.hasError)
            XCTAssertEqual(self.viewModel.currentError?.title, "Error")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testLoadWithCustomErrorTitle() {
        // Given
        let expectation = XCTestExpectation(description: "Load with custom title")

        // When
        viewModel.load(errorTitle: "Network Error") {
            throw NSError(domain: "Test", code: -1)
        }

        // Then
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.currentError?.title, "Network Error")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testLoadWithLoadingStyle() {
        // Given
        let expectation = XCTestExpectation(description: "Load with custom style")

        // When
        viewModel.load(style: .inline) {
            // empty work
        }

        // Then
        XCTAssertEqual(viewModel.loadingStyle, .inline)
        XCTAssertEqual(viewModel.phase, .loading)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.phase, .content)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testLoadErrorHasRetryAction() {
        // Given
        let expectation = XCTestExpectation(description: "Error has retry")

        // When
        viewModel.load {
            throw NSError(domain: "Test", code: -1)
        }

        // Then
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertNotNil(self.viewModel.currentError?.retry)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Computed Property Tests

    func testIsLoading_True() {
        // When
        viewModel.setLoading()

        // Then
        XCTAssertTrue(viewModel.isLoading)
    }

    func testIsLoading_False() {
        // When
        viewModel.setContent()

        // Then
        XCTAssertFalse(viewModel.isLoading)
    }

    func testIsContent_True() {
        // When
        viewModel.setContent()

        // Then
        XCTAssertTrue(viewModel.isContent)
    }

    func testIsContent_False() {
        // When
        viewModel.setLoading()

        // Then
        XCTAssertFalse(viewModel.isContent)
    }

    func testIsEmpty_True() {
        // When
        viewModel.setEmpty()

        // Then
        XCTAssertTrue(viewModel.isEmpty)
    }

    func testIsEmpty_False() {
        // When
        viewModel.setLoading()

        // Then
        XCTAssertFalse(viewModel.isEmpty)
    }

    func testHasError_True() {
        // When
        viewModel.setError(title: "Error", message: "Test")

        // Then
        XCTAssertTrue(viewModel.hasError)
    }

    func testHasError_False() {
        // When
        viewModel.setLoading()

        // Then
        XCTAssertFalse(viewModel.hasError)
    }

    func testIsIdle_True() {
        // When (initial state is idle)

        // Then
        XCTAssertTrue(viewModel.isIdle)
    }

    func testIsIdle_False() {
        // When
        viewModel.setLoading()

        // Then
        XCTAssertFalse(viewModel.isIdle)
    }

    func testCurrentError_WhenError() {
        // Given
        let error = ScreenError(title: "Test", message: "Message")

        // When
        viewModel.setError(error)

        // Then
        XCTAssertEqual(viewModel.currentError, error)
    }

    func testCurrentError_WhenNotError() {
        // When
        viewModel.setContent()

        // Then
        XCTAssertNil(viewModel.currentError)
    }

    // MARK: - Multiple State Transitions Tests

    func testMultipleStateTransitions() {
        // Given
        XCTAssertEqual(viewModel.phase, .idle)

        // When
        viewModel.setLoading()
        XCTAssertEqual(viewModel.phase, .loading)

        viewModel.setContent()
        XCTAssertEqual(viewModel.phase, .content)

        viewModel.setEmpty()
        XCTAssertEqual(viewModel.phase, .empty)

        let error = ScreenError(title: "E", message: "M")
        viewModel.setError(error)
        XCTAssertTrue(viewModel.hasError)

        viewModel.setIdle()
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func testAlertAndBannerCanBothDisplay() {
        // Given
        let alert = AlertState.info(title: "Alert", message: "Alert msg")
        let banner = BannerState.success("Banner msg")

        // When
        viewModel.showAlert(alert)
        viewModel.showBanner(banner)

        // Then
        XCTAssertNotNil(viewModel.alert)
        XCTAssertNotNil(viewModel.banner)
    }

    func testReplaceAlertWithNewAlert() {
        // Given
        let alert1 = AlertState.info(title: "Alert 1", message: "Message 1")
        let alert2 = AlertState.info(title: "Alert 2", message: "Message 2")

        // When
        viewModel.showAlert(alert1)
        let firstID = viewModel.alert?.id
        viewModel.showAlert(alert2)
        let secondID = viewModel.alert?.id

        // Then
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(viewModel.alert?.title, "Alert 2")
    }

    func testReplaceBannerWithNewBanner() {
        // Given
        let banner1 = BannerState.success("Banner 1")
        let banner2 = BannerState.error("Banner 2")

        // When
        viewModel.showBanner(banner1)
        let firstID = viewModel.banner?.id
        viewModel.showBanner(banner2)
        let secondID = viewModel.banner?.id

        // Then
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(viewModel.banner?.message, "Banner 2")
    }

    // MARK: - Published Properties Tests

    func testPhasePublishesChanges() {
        // Given
        let expectation = XCTestExpectation(description: "Phase publishes")
        var phaseValues: [ViewPhase] = []

        viewModel.$phase
            .dropFirst() // Skip initial value
            .sink { phase in
                phaseValues.append(phase)
                if phaseValues.count == 1 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        viewModel.setLoading()

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(phaseValues.count, 1)
        XCTAssertEqual(phaseValues[0], .loading)
    }

    func testAlertPublishesChanges() {
        // Given
        let expectation = XCTestExpectation(description: "Alert publishes")
        var alertValues: [AlertState?] = []

        viewModel.$alert
            .dropFirst()
            .sink { alert in
                alertValues.append(alert)
                if alertValues.count == 1 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        let alert = AlertState.info(title: "Test", message: "Test")
        viewModel.showAlert(alert)

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(alertValues.count, 1)
    }

    func testBannerPublishesChanges() {
        // Given
        let expectation = XCTestExpectation(description: "Banner publishes")
        var bannerValues: [BannerState?] = []

        viewModel.$banner
            .dropFirst()
            .sink { banner in
                bannerValues.append(banner)
                if bannerValues.count == 1 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        let banner = BannerState.success("Test")
        viewModel.showBanner(banner)

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(bannerValues.count, 1)
    }
}
