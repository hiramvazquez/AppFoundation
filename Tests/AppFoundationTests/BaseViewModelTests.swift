import Testing
import Foundation
@testable import AppFoundation

@Suite("BaseViewModel")
struct BaseViewModelTests {
    let viewModel = BaseViewModel()

    // MARK: - Initial State

    @Test func initialState() {
        #expect(viewModel.phase == .idle)
        #expect(viewModel.loadingStyle == .fullScreen)
        #expect(viewModel.activity == ActivityState.none)
        #expect(viewModel.alert == nil)
        #expect(viewModel.banner == nil)
    }

    // MARK: - Phase Transitions

    @Test(arguments: [LoadingStyle.fullScreen, .inline, .overlay])
    func setLoadingAppliesStyle(style: LoadingStyle) {
        viewModel.setLoading(style)
        #expect(viewModel.phase == .loading)
        #expect(viewModel.loadingStyle == style)
    }

    @Test func setLoadingDefaultsToFullScreen() {
        viewModel.setLoading()
        #expect(viewModel.phase == .loading)
        #expect(viewModel.loadingStyle == .fullScreen)
    }

    @Test func setContent() {
        viewModel.setContent()
        #expect(viewModel.phase == .content)
    }

    @Test func setEmpty() {
        viewModel.setEmpty()
        #expect(viewModel.phase == .empty)
    }

    @Test func setErrorWithScreenError() {
        let error = ScreenError(title: "Test Error", message: "Something went wrong")
        viewModel.setError(error)
        #expect(viewModel.hasError)
        #expect(viewModel.currentError == error)
    }

    @Test func setErrorWithTitleAndMessage() {
        viewModel.setError(title: "Network Error", message: "Failed to connect")
        #expect(viewModel.currentError?.title == "Network Error")
        #expect(viewModel.currentError?.message == "Failed to connect")
    }

    @Test func setErrorWithRetryAction() {
        var retryWasCalled = false
        viewModel.setError(title: "Error", message: "Retry me", retry: { retryWasCalled = true })
        viewModel.currentError?.retry?()
        #expect(retryWasCalled)
    }

    @Test func setIdleResetsPhase() {
        viewModel.setContent()
        viewModel.setIdle()
        #expect(viewModel.phase == .idle)
    }

    @Test func multipleStateTransitions() {
        viewModel.setLoading()
        #expect(viewModel.phase == .loading)
        viewModel.setContent()
        #expect(viewModel.phase == .content)
        viewModel.setEmpty()
        #expect(viewModel.phase == .empty)
        viewModel.setError(ScreenError(title: "E", message: "M"))
        #expect(viewModel.hasError)
        viewModel.setIdle()
        #expect(viewModel.phase == .idle)
    }

    // MARK: - Secondary Activity

    @Test func startAndStopActivity() {
        viewModel.startActivity(.overlay)
        #expect(viewModel.activity == .loading(.overlay))
        #expect(viewModel.isPerformingActivity)

        viewModel.stopActivity()
        #expect(viewModel.activity == ActivityState.none)
        #expect(!viewModel.isPerformingActivity)
    }

    // MARK: - Alerts

    @Test func showAndDismissAlert() {
        viewModel.showAlert(.info(title: "Info", message: "This is info"))
        #expect(viewModel.alert?.title == "Info")

        viewModel.dismissAlert()
        #expect(viewModel.alert == nil)
    }

    @Test func confirmationAlertRunsConfirmAction() {
        var confirmWasCalled = false
        viewModel.showAlert(.confirmation(
            title: "Confirm?", message: "Are you sure?",
            confirm: "Yes", cancel: "No",
            onConfirm: { confirmWasCalled = true }
        ))
        viewModel.alert?.primaryButton.action()
        #expect(confirmWasCalled)
    }

    @Test func destructiveAlertHasDestructiveRole() {
        viewModel.showAlert(.destructive(
            title: "Delete?", message: "Cannot undo",
            confirm: "Delete", cancel: "Cancel",
            onConfirm: {}
        ))
        #expect(viewModel.alert?.primaryButton.role == .destructive)
    }

    @Test func replaceAlertWithNewAlert() {
        viewModel.showAlert(.info(title: "Alert 1", message: "Message 1"))
        let firstID = viewModel.alert?.id
        viewModel.showAlert(.info(title: "Alert 2", message: "Message 2"))
        #expect(viewModel.alert?.id != firstID)
        #expect(viewModel.alert?.title == "Alert 2")
    }

    // MARK: - Banners

    @Test func showBannerStyles() {
        viewModel.showBanner(.success("Saved!"))
        #expect(viewModel.banner?.message == "Saved!")
        #expect(viewModel.banner?.style == .success)

        viewModel.showBanner(.error("Failed!"))
        #expect(viewModel.banner?.style == .error)

        viewModel.showBanner(.info("Info"))
        #expect(viewModel.banner?.style == .info)

        viewModel.showBanner(.warning("Warning"))
        #expect(viewModel.banner?.style == .warning)
    }

    @Test func dismissBanner() {
        viewModel.showBanner(.success("Saved!"))
        viewModel.dismissBanner()
        #expect(viewModel.banner == nil)
    }

    @Test func replaceBannerWithNewBanner() {
        viewModel.showBanner(.success("Banner 1"))
        let firstID = viewModel.banner?.id
        viewModel.showBanner(.error("Banner 2"))
        #expect(viewModel.banner?.id != firstID)
        #expect(viewModel.banner?.message == "Banner 2")
    }

    @Test func alertAndBannerCanBothDisplay() {
        viewModel.showAlert(.info(title: "Alert", message: "Alert msg"))
        viewModel.showBanner(.success("Banner msg"))
        #expect(viewModel.alert != nil)
        #expect(viewModel.banner != nil)
    }

    // MARK: - performLoad

    @Test func loadSuccessSetsContent() async throws {
        var workWasExecuted = false
        viewModel.performLoad {
            workWasExecuted = true
        }
        try await waitUntil { viewModel.phase == .content }
        #expect(workWasExecuted)
        #expect(viewModel.phase == .content)
    }

    @Test func loadFailureSetsErrorWithDefaultTitle() async throws {
        viewModel.performLoad {
            throw TestError("boom")
        }
        try await waitUntil { viewModel.hasError }
        #expect(viewModel.currentError?.title == "Error")
    }

    @Test func loadFailureUsesCustomErrorTitle() async throws {
        viewModel.performLoad(errorTitle: "Network Error") {
            throw TestError()
        }
        try await waitUntil { viewModel.hasError }
        #expect(viewModel.currentError?.title == "Network Error")
    }

    @Test func loadAppliesLoadingStyleImmediately() async throws {
        viewModel.performLoad(style: .inline) {}
        #expect(viewModel.loadingStyle == .inline)
        #expect(viewModel.phase == .loading)
        try await waitUntil { viewModel.phase == .content }
    }

    @Test func loadErrorProvidesRetryAction() async throws {
        viewModel.performLoad {
            throw TestError()
        }
        try await waitUntil { viewModel.hasError }
        #expect(viewModel.currentError?.retry != nil)
    }

    // MARK: - Computed Helpers

    @Test func computedHelpersReflectPhase() {
        #expect(viewModel.isIdle)

        viewModel.setLoading()
        #expect(viewModel.isLoading && !viewModel.isContent && !viewModel.isEmpty && !viewModel.hasError && !viewModel.isIdle)

        viewModel.setContent()
        #expect(viewModel.isContent && !viewModel.isLoading)
        #expect(viewModel.currentError == nil)

        viewModel.setEmpty()
        #expect(viewModel.isEmpty)

        viewModel.setError(ScreenError(title: "T", message: "M"))
        #expect(viewModel.hasError)
        #expect(viewModel.currentError == ScreenError(title: "T", message: "M"))
    }
}
