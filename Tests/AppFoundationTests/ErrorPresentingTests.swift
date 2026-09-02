import Testing
import Foundation
@testable import AppFoundation

// MARK: - Test doubles

private nonisolated struct MarkedError: Error {}

private nonisolated struct ConvertibleError: Error, AppErrorConvertible {
    var screenError: ScreenError {
        ScreenError(title: "Convertible", message: "Convertible message")
    }
}

private nonisolated struct LocalizedOnlyError: Error, LocalizedError {
    var errorDescription: String? { "Localized description" }
}

private nonisolated struct SilentLocalizedError: Error, LocalizedError {
    var errorDescription: String? { nil }
}

private nonisolated struct MockPresenter: ErrorPresenting {
    let name: String
    func screenError(for error: any Error, fallbackTitle: String, retry: Action?) -> ScreenError {
        ScreenError(title: name, message: name, retry: retry)
    }
}

// MARK: - DefaultErrorPresenter

@Suite("ErrorPresenting — DefaultErrorPresenter")
struct DefaultErrorPresenterTests {
    let presenter = DefaultErrorPresenter()

    @Test func appErrorConvertibleWinsFirst() {
        let result = presenter.screenError(for: ConvertibleError(), fallbackTitle: "Fallback", retry: nil)
        #expect(result.title == "Convertible")
        #expect(result.message == "Convertible message")
    }

    @Test func appErrorConvertibleRetryIsOverriddenWhenProvided() {
        var externalRetryCalled = false
        let result = presenter.screenError(
            for: ConvertibleError(),
            fallbackTitle: "Fallback",
            retry: { externalRetryCalled = true }
        )
        result.retry?()
        #expect(externalRetryCalled)
    }

    @Test func localizedErrorWithDescriptionUsesFallbackTitleAndDescription() {
        let result = presenter.screenError(for: LocalizedOnlyError(), fallbackTitle: "Fallback", retry: nil)
        #expect(result.title == "Fallback")
        #expect(result.message == "Localized description")
    }

    @Test func localizedErrorWithoutDescriptionFallsThroughToGeneric() {
        let result = presenter.screenError(for: SilentLocalizedError(), fallbackTitle: "Fallback", retry: nil)
        #expect(result.title == "Fallback")
        #expect(result.message == L10n.genericErrorMessage)
    }

    @Test func foreignErrorUsesFallbackTitleAndGenericMessage() {
        let result = presenter.screenError(for: MarkedError(), fallbackTitle: "Fallback", retry: nil)
        #expect(result.title == "Fallback")
        #expect(result.message == L10n.genericErrorMessage)
        // La cadena que producía `localizedDescription` para un enum ajeno nunca debe aparecer.
        #expect(!result.message.contains("couldn't be completed"))
    }

    @Test func foreignErrorPreservesRetry() {
        var retryCalled = false
        let result = presenter.screenError(for: MarkedError(), fallbackTitle: "Fallback", retry: { retryCalled = true })
        result.retry?()
        #expect(retryCalled)
    }
}

// MARK: - Precedence: instance > static > default

/// `.serialized`: estos tests mutan `BaseViewModel.errorPresenter`, un `static var`
/// global — con ejecución paralela entre tests del propio suite se pisarían entre sí.
/// Ningún otro fichero de test toca `errorPresenter`/`cancellationRecognizer`, así que
/// serializar este suite basta (no hay contaminación cruzada con otros suites).
@Suite("ErrorPresenting — precedencia en BaseViewModel", .serialized)
struct ErrorPresenterPrecedenceTests {
    /// Restaura el estático al valor por defecto tras cada test — es un `static var`
    /// global y otros tests (en el mismo proceso) asumen `DefaultErrorPresenter`.
    private func resetStaticPresenter() {
        BaseViewModel.errorPresenter = DefaultErrorPresenter()
    }

    @Test func defaultIsUsedWhenNothingIsConfigured() async throws {
        defer { resetStaticPresenter() }
        resetStaticPresenter()

        let vm = BaseViewModel()
        let task = vm.performLoad { _ in throw MarkedError() }
        await task.value

        #expect(vm.currentError?.message == L10n.genericErrorMessage)
    }

    @Test func staticPresenterOverridesDefault() async throws {
        defer { resetStaticPresenter() }
        BaseViewModel.errorPresenter = MockPresenter(name: "static-presenter")

        let vm = BaseViewModel()
        let task = vm.performLoad { _ in throw MarkedError() }
        await task.value

        #expect(vm.currentError?.title == "static-presenter")
    }

    @Test func instancePresenterOverridesStatic() async throws {
        defer { resetStaticPresenter() }
        BaseViewModel.errorPresenter = MockPresenter(name: "static-presenter")

        let vm = BaseViewModel(errorPresenter: MockPresenter(name: "instance-presenter"))
        let task = vm.performLoad { _ in throw MarkedError() }
        await task.value

        #expect(vm.currentError?.title == "instance-presenter")
    }

    @Test func instancePresenterAppliesToActivityErrorsToo() async throws {
        defer { resetStaticPresenter() }

        let vm = BaseViewModel(errorPresenter: MockPresenter(name: "instance-presenter"))
        let task = vm.performActivity(errorHandling: .alert) { _ in throw MarkedError() }
        await task.value

        #expect(vm.alert?.title == "instance-presenter")
    }
}

// MARK: - CancellationRecognizing

/// `.serialized`: `customCancellationRecognizerIsConsulted` mutates
/// `BaseViewModel.cancellationRecognizer`, a global `static var` other tests in this
/// suite read the default of.
@Suite("CancellationRecognizing", .serialized)
struct CancellationRecognizingTests {
    let recognizer = DefaultCancellationRecognizer()

    @Test func recognizesTypedCancellationError() {
        #expect(recognizer.isCancellation(CancellationError()))
    }

    @Test func recognizesURLErrorCancelled() {
        #expect(recognizer.isCancellation(URLError(.cancelled)))
    }

    @Test func doesNotRecognizeOtherURLErrors() {
        #expect(!recognizer.isCancellation(URLError(.notConnectedToInternet)))
    }

    @Test func doesNotRecognizeUnrelatedErrors() {
        #expect(!recognizer.isCancellation(MarkedError()))
    }

    /// AF-04: `performLoad` reconoce `URLError(.cancelled)`, no solo `CancellationError`
    /// tipado — nunca debe surgir como fase `.error`.
    @Test func urlErrorCancelledInLoadDoesNotSurfaceAsScreenError() async {
        let vm = BaseViewModel()
        let task = vm.performLoad { _ in throw URLError(.cancelled) }
        await task.value

        #expect(!vm.hasError)
    }

    @Test func customCancellationRecognizerIsConsulted() async {
        struct AppCancellationRecognizer: CancellationRecognizing {
            func isCancellation(_ error: any Error) -> Bool {
                (error as? MarkedError) != nil
            }
        }
        let previous = BaseViewModel.cancellationRecognizer
        BaseViewModel.cancellationRecognizer = AppCancellationRecognizer()
        defer { BaseViewModel.cancellationRecognizer = previous }

        let vm = BaseViewModel()
        let task = vm.performLoad { _ in throw MarkedError() }
        await task.value

        #expect(!vm.hasError)
    }
}
