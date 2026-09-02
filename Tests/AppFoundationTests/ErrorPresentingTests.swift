import Foundation
import Testing

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

/// Every test here injects its presenter through the initializer (DC-AF-3,
/// `AUDITORIA-2026-09-02-doblecheck.md` §3) — none mutates the global
/// `BaseViewModel.errorPresenter`, so nothing here can race with a parallel suite. The one
/// test that genuinely needs to touch the static (because it's the thing being tested)
/// lives in `ErrorPresenterStaticDefaultTests` below.
@Suite("ErrorPresenting — precedencia por instancia en BaseViewModel")
struct ErrorPresenterPrecedenceTests {
    @Test func instancePresenterOverridesWhateverIsStatic() async throws {
        let vm = BaseViewModel(errorPresenter: MockPresenter(name: "instance-presenter"))
        let task = vm.performLoad { _ in throw MarkedError() }
        await task.value

        #expect(vm.currentError?.title == "instance-presenter")
    }

    @Test func instancePresenterAppliesToActivityErrorsToo() async throws {
        let vm = BaseViewModel(errorPresenter: MockPresenter(name: "instance-presenter"))
        let task = vm.performActivity(errorHandling: .alert) { _ in throw MarkedError() }
        await task.value

        #expect(vm.alert?.title == "instance-presenter")
    }

    /// Criterio de aceptación literal del PRD: un `enum` de dominio plano, sin
    /// `AppErrorConvertible` ni `LocalizedError`, produce
    /// `ScreenError(title: L10n.error, message: L10n.genericErrorMessage)` — nunca la
    /// cadena de `localizedDescription` que Foundation compone para un tipo Swift ajeno.
    /// Exercised through an explicit instance override (`DefaultErrorPresenter()`) instead
    /// of the static default — the presenter's behavior is identical either way, and this
    /// keeps the assertion independent of `BaseViewModel.errorPresenter`'s current value.
    @Test func plainDomainEnumProducesGenericLocalizedScreenError() async throws {
        enum Foo: Error { case bar }

        let vm = BaseViewModel(errorPresenter: DefaultErrorPresenter())
        let task = vm.performLoad { _ in throw Foo.bar }
        await task.value

        #expect(vm.currentError == ScreenError(title: L10n.error, message: L10n.genericErrorMessage))
        #expect(!(vm.currentError?.message.contains("couldn't be completed") ?? false))
    }
}

/// `.serialized`: the only test left anywhere in `AppFoundation/Tests` that mutates
/// `BaseViewModel.errorPresenter`, a global `static var` — kept because it's the one thing
/// that genuinely needs the static: the fallback chain when nothing is injected per
/// instance, and the static overriding the built-in default. Every other precedence test
/// (`ErrorPresenterPrecedenceTests` above) uses per-instance injection instead, precisely
/// to avoid this test's residual flake risk (DC-AF-3): a parallel suite reading
/// `BaseViewModel.errorPresenter` while this one is mutating it. `.serialized` only
/// protects this suite's own (single) test from other tests within it — it can't protect
/// against unrelated suites running concurrently, which is why every other precedence test
/// no longer needs the static at all.
@Suite("ErrorPresenting — estático por defecto en BaseViewModel", .serialized)
struct ErrorPresenterStaticDefaultTests {
    @Test func staticErrorPresenterDefaultsAndCanBeOverridden() async throws {
        let original = BaseViewModel.errorPresenter
        defer { BaseViewModel.errorPresenter = original }

        // Nothing injected per instance, static explicitly at its documented default.
        BaseViewModel.errorPresenter = DefaultErrorPresenter()
        let defaultVM = BaseViewModel()
        let defaultTask = defaultVM.performLoad { _ in throw MarkedError() }
        await defaultTask.value
        #expect(defaultVM.currentError?.message == L10n.genericErrorMessage)

        // The static overrides the built-in default when nothing is injected per instance.
        BaseViewModel.errorPresenter = MockPresenter(name: "static-presenter")
        let staticVM = BaseViewModel()
        let staticTask = staticVM.performLoad { _ in throw MarkedError() }
        await staticTask.value
        #expect(staticVM.currentError?.title == "static-presenter")
    }
}

// MARK: - CancellationRecognizing

@Suite("CancellationRecognizing")
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

    /// DC-AF-3: injected per instance, never through the `static var` — a custom
    /// recognizer configured for one test can't leak into a suite running in parallel.
    @Test func customCancellationRecognizerIsConsulted() async {
        struct AppCancellationRecognizer: CancellationRecognizing {
            func isCancellation(_ error: any Error) -> Bool {
                (error as? MarkedError) != nil
            }
        }

        let vm = BaseViewModel(cancellationRecognizer: AppCancellationRecognizer())
        let task = vm.performLoad { _ in throw MarkedError() }
        await task.value

        #expect(!vm.hasError)
    }
}
