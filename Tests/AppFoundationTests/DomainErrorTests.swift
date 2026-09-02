import Testing

@testable import AppFoundation

// MARK: - ARQUITECTURA-KIT-2026-09-02.md §8, M1: `DomainError`

private enum SampleError: DomainError, Equatable {
    case retryable
    case notRetryable

    var isRetryable: Bool {
        switch self {
        case .retryable: true
        case .notRetryable: false
        }
    }

    var screenError: ScreenError {
        switch self {
        case .retryable: ScreenError(title: "Retryable", message: "Try again.")
        case .notRetryable: ScreenError(title: "Not retryable", message: "Nothing to do.")
        }
    }
}

/// Conforms `DomainError` (inherited default `isRetryable`) without overriding it.
private struct DefaultRetryableError: DomainError {
    var screenError: ScreenError { ScreenError(title: "Default", message: "Default message.") }
}

@Suite("DomainError (ARQUITECTURA-KIT-2026-09-02.md §8, M1)")
struct DomainErrorTests {
    @Test("The default isRetryable is false when a conformance doesn't override it")
    func defaultIsRetryableIsFalse() {
        #expect(DefaultRetryableError().isRetryable == false)
    }

    @Test("isRetryable is per-case when a conformance overrides it")
    func isRetryableIsPerCase() {
        #expect(SampleError.retryable.isRetryable)
        #expect(!SampleError.notRetryable.isRetryable)
    }

    @Test("A DomainError is also an AppErrorConvertible — DefaultErrorPresenter resolves it")
    func domainErrorPresentsItself() {
        let presented = DefaultErrorPresenter().screenError(
            for: SampleError.retryable,
            fallbackTitle: "Fallback",
            retry: nil
        )

        #expect(presented.title == "Retryable")
        #expect(presented.message == "Try again.")
    }
}
