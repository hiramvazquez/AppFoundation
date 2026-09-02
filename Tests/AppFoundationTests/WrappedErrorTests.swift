import Foundation
import Testing

@testable import AppFoundation

// MARK: - Cierre de cobertura: WrappedError estaba al 0%

@Suite("WrappedError")
struct WrappedErrorTests {
    @Test func messageCombinesContextAndUnderlying() {
        let wrapped = WrappedError(underlying: TestError("boom"), context: "Loading profile")
        #expect(wrapped.message == "Loading profile: boom")
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

    /// WrappedError ES AppErrorConvertible: performLoad muestra su mensaje, no el crudo.
    @Test func screenErrorUsesLocalizedTitleAndComposedMessage() {
        let wrapped = WrappedError(underlying: TestError("timeout"), context: "Syncing")
        let screenError = wrapped.screenError

        #expect(screenError.title == L10n.error)
        #expect(screenError.message == "Syncing: timeout")
    }

    @Test func performLoadSurfacesWrappedErrorMessage() async {
        let viewModel = BaseViewModel()
        let task = viewModel.performLoad { _ in
            throw WrappedError(underlying: TestError("offline"), context: "Loading feed")
        }
        await task.value

        #expect(viewModel.currentError?.message == "Loading feed: offline")
    }

    @Test func equalityComparesContextCodeAndUnderlyingDescription() {
        let a = WrappedError(underlying: TestError("x"), context: "ctx", code: "C1")
        let b = WrappedError(underlying: TestError("x"), context: "ctx", code: "C1")
        let c = WrappedError(underlying: TestError("y"), context: "ctx", code: "C1")

        #expect(a == b)
        #expect(a != c)
    }

    @Test func localizedErrorConformanceExposesMessageAndReason() {
        let wrapped = WrappedError(underlying: TestError("cause"), context: "Op")
        #expect(wrapped.errorDescription == "Op: cause")
        #expect(wrapped.failureReason == "cause")
    }

    @Test func descriptionIncludesCodeWhenPresent() {
        let wrapped = WrappedError(underlying: TestError(), context: "Op", code: "OP_1")
        #expect(wrapped.description.contains("Code: OP_1"))
        #expect(wrapped.debugDescription.contains("Op"))
    }
}
