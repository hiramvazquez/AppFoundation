import Foundation
import Testing

@testable import AppFoundation

// MARK: - Cierre de cobertura: WrappedError estaba al 0%

@Suite("WrappedError")
struct WrappedErrorTests {
    /// HALLAZGO 1: `message` (y por tanto `screenError`/`errorDescription`) nunca debe
    /// componer `context` o el texto de `underlying` — ambos pueden traer PII, rutas de
    /// fichero o texto de servidor que el desarrollador nunca vetó para pantalla. Debe ser,
    /// siempre, el mismo genérico localizado que usa `DefaultErrorPresenter` para cualquier
    /// error que no sabe presentar.
    @Test func messageIsAlwaysTheGenericFallbackNeverContextOrUnderlying() {
        let wrapped = WrappedError(
            underlying: TestError("user john@acme.com not found at /var/db/users.sqlite"),
            context: "Loading profile"
        )

        #expect(wrapped.message == L10n.genericErrorMessage)
        #expect(!wrapped.message.contains("john@acme.com"))
        #expect(!wrapped.message.contains("Loading profile"))
    }

    /// La información técnica completa sigue disponible ÍNTEGRA por la vía de depuración:
    /// nada de esto se toca al cerrar el hallazgo — solo `message`/`screenError`/
    /// `errorDescription`/`failureReason` (los canales que llegan, directa o
    /// ambientalmente, a la pantalla).
    @Test func debugChannelsStayCompleteAfterClosingTheScreenLeak() {
        let underlying = TestError("user john@acme.com not found")
        let wrapped = WrappedError(underlying: underlying, context: "Loading profile", code: "PROFILE_001")

        #expect(wrapped.context == "Loading profile")
        #expect(wrapped.code == "PROFILE_001")
        #expect(wrapped.underlying as? TestError == underlying)
        #expect(wrapped.rootCause as? TestError == underlying)
        #expect(wrapped.contextChain == ["Loading profile"])
        #expect(wrapped.description.contains("john@acme.com"))
        #expect(wrapped.description.contains("Loading profile"))
        #expect(wrapped.description.contains("PROFILE_001"))
        #expect(wrapped.debugDescription.contains("john@acme.com"))
    }

    @Test func rootCauseUnwrapsNestedWrappedErrors() {
        let root = TestError("root")
        let inner = WrappedError(underlying: root, context: "inner")
        let outer = WrappedError(underlying: inner, context: "outer")

        #expect(outer.rootCause as? TestError == root)
    }

    @Test func contextChainListsOutermostFirst() {
        let inner = WrappedError(underlying: TestError(), context: "inner")
        let middle = WrappedError(underlying: inner, context: "middle")
        let outer = WrappedError(underlying: middle, context: "outer")

        #expect(outer.contextChain == ["outer", "middle", "inner"])
    }

    @Test func wrappedExtensionBuildsWrappedError() {
        let wrapped = TestError("fail").wrapped(context: "Fetching catalog", code: "CAT_001")

        #expect(wrapped.context == "Fetching catalog")
        #expect(wrapped.code == "CAT_001")
        #expect(wrapped.underlying as? TestError == TestError("fail"))
    }

    /// WrappedError ES AppErrorConvertible: performLoad muestra el genérico, nunca el crudo.
    @Test func screenErrorUsesLocalizedTitleAndGenericMessage() {
        let wrapped = WrappedError(underlying: TestError("timeout"), context: "Syncing")
        let screenError = wrapped.screenError

        #expect(screenError.title == L10n.error)
        #expect(screenError.message == L10n.genericErrorMessage)
        #expect(!screenError.message.contains("timeout"))
        #expect(!screenError.message.contains("Syncing"))
    }

    @Test func performLoadSurfacesGenericMessageNeverTheUnderlyingText() async {
        let viewModel = BaseViewModel()
        let task = viewModel.performLoad { _ in
            throw WrappedError(underlying: TestError("offline"), context: "Loading feed")
        }
        await task.value

        #expect(viewModel.currentError?.message == L10n.genericErrorMessage)
        #expect(!(viewModel.currentError?.message.contains("offline") ?? true))
        #expect(!(viewModel.currentError?.message.contains("Loading feed") ?? true))
    }

    @Test func equalityComparesContextCodeAndUnderlyingDescription() {
        let a = WrappedError(underlying: TestError("x"), context: "ctx", code: "C1")
        let b = WrappedError(underlying: TestError("x"), context: "ctx", code: "C1")
        let c = WrappedError(underlying: TestError("y"), context: "ctx", code: "C1")

        #expect(a == b)
        #expect(a != c)
    }

    /// `errorDescription` alimenta `Error.localizedDescription`, un canal AMBIENTAL que no
    /// pasa por `ErrorPresenting` — cualquier código que lo lea directamente (un reporter de
    /// crashes, una alerta construida a mano) debe ver el mismo genérico que `screenError`,
    /// nunca `cause`. `failureReason` (pensado también para mostrarse,
    /// `NSError.localizedFailureReason`) deja de ser una segunda vía para la misma fuga.
    @Test func localizedErrorConformanceNeverExposesUnderlyingText() {
        let wrapped = WrappedError(underlying: TestError("cause"), context: "Op")
        #expect(wrapped.errorDescription == L10n.genericErrorMessage)
        #expect(wrapped.failureReason == nil)
        #expect(wrapped.localizedDescription == L10n.genericErrorMessage)
    }

    /// `recoverySuggestion` sigue reenviándose: es el underlying, no WrappedError, quien
    /// decide mostrar ese texto — lo escribió su propio autor para pantalla.
    @Test func recoverySuggestionIsForwardedFromAnUnderlyingLocalizedError() {
        struct RecoverableError: Error, LocalizedError {
            var recoverySuggestion: String? { "Try again in a moment." }
        }
        let wrapped = WrappedError(underlying: RecoverableError(), context: "Op")
        #expect(wrapped.recoverySuggestion == "Try again in a moment.")
    }

    @Test func descriptionIncludesCodeWhenPresent() {
        let wrapped = WrappedError(underlying: TestError(), context: "Op", code: "OP_1")
        #expect(wrapped.description.contains("Code: OP_1"))
        #expect(wrapped.debugDescription.contains("Op"))
    }
}
