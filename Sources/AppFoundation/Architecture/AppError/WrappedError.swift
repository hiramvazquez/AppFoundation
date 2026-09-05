import Foundation

/// A wrapper that preserves the original error while adding context.
///
/// Use this when you need to catch errors and add additional context
/// without losing the original error information.
///
/// ## Example - Basic Usage
/// ```swift
/// do {
///     try await loadData()
/// } catch {
///     throw WrappedError(underlying: error, context: "Loading user profile")
/// }
/// ```
///
/// ## Example - With Error Code
/// ```swift
/// do {
///     try await service.fetch()
/// } catch {
///     throw WrappedError(
///         underlying: error,
///         context: "Fetching catalog",
///         code: "CATALOG_FETCH_001"  // For analytics/tracking
///     )
/// }
/// ```
///
/// ## Example - In ViewModel
/// ```swift
/// do {
///     data = try await service.fetch()
/// } catch {
///     let wrapped = WrappedError(
///         underlying: error,
///         context: "Fetching catalog",
///         code: "VM_FETCH_ERROR",
///         file: #fileID,
///         line: #line
///     )
///     setError(wrapped.screenError)
/// }
/// ```
///
/// ## Screen text vs. debug text
///
/// `screenError`/`message`/`errorDescription` (`Error.localizedDescription`) are always the
/// generic, localized fallback — never `context` or `underlying`, which can carry PII, file
/// paths, or raw server/SDK text you never vetted for display. The full technical detail is
/// still there, just not through those: log ``description``/``debugDescription``, or read
/// ``underlying``, ``context``, ``rootCause``, and ``contextChain`` directly.
public nonisolated struct WrappedError: Error, Sendable, CustomStringConvertible {
    /// The original error that was caught.
    public let underlying: Error

    /// Human-readable context describing what operation failed.
    public let context: String

    /// Optional error code for analytics, logging, and tracking.
    ///
    /// Use consistent codes across your app for easier debugging and metrics.
    /// Examples: "AUTH_001", "NETWORK_TIMEOUT", "PARSE_ERROR"
    public let code: String?

    /// The file where the error was wrapped (for debugging).
    ///
    /// `#fileID` (`"Module/File.swift"`), not `#file`: `#file` embeds the absolute build
    /// path of the source file in the binary, which `#fileID` avoids.
    public let file: String

    /// The line number where the error was wrapped (for debugging).
    public let line: Int

    /// The timestamp when the error was wrapped.
    public let timestamp: Date

    /// Creates a wrapped error with context.
    ///
    /// - Parameters:
    ///   - underlying: The original error.
    ///   - context: Description of the operation that failed.
    ///   - code: Optional error code for analytics and tracking.
    ///   - file: The file where the error occurred (auto-filled, `#fileID`).
    ///   - line: The line where the error occurred (auto-filled).
    ///   - now: Clock used to stamp `timestamp`. Injectable for deterministic tests;
    ///     defaults to `Date.init`.
    public init(
        underlying: Error,
        context: String,
        code: String? = nil,
        file: String = #fileID,
        line: Int = #line,
        now: () -> Date = Date.init
    ) {
        self.underlying = underlying
        self.context = context
        self.code = code
        self.file = file
        self.line = line
        self.timestamp = now()
    }

    /// The safe, user-facing error message: always the generic localized fallback
    /// (`L10n.genericErrorMessage`), never `context` or `underlying`.
    ///
    /// This is what `screenError` and `errorDescription` (hence `Error.localizedDescription`)
    /// show. `context` is developer-authored (`"Loading user profile"`, not localized, not
    /// written for an end user) and `underlying` can come from a third-party SDK or a data
    /// layer and may embed PII, file paths, or raw server text — neither is safe to put on
    /// screen, for the exact reason `DefaultErrorPresenter` never shows a foreign error's
    /// `localizedDescription`.
    ///
    /// For the full technical detail — needed to reconstruct what actually happened, e.g. in
    /// logs or a crash report — use ``description``, ``debugDescription``, ``rootCause``, or
    /// ``contextChain`` instead. Those are unaffected by this and stay complete.
    public var message: String {
        // No componer nada a partir de `context`/`underlying` aquí: es precisamente la puerta
        // de atrás que este tipo abría antes (ver WrappedErrorTests / CHANGELOG). El detalle
        // técnico sigue disponible íntegro por la vía de depuración (description,
        // debugDescription, rootCause, contextChain) — nunca por esta.
        L10n.genericErrorMessage
    }

    /// Detailed description for debugging.
    public var description: String {
        var desc = """
            WrappedError:
              Context: \(context)
            """
        if let code = code {
            desc += "\n  Code: \(code)"
        }
        desc += """

              Underlying: \(underlying)
              File: \(file):\(line)
              Time: \(timestamp)
            """
        return desc
    }

    /// The root cause error, unwrapping any nested WrappedErrors.
    public var rootCause: Error {
        var current: Error = underlying
        while let wrapped = current as? WrappedError {
            current = wrapped.underlying
        }
        return current
    }

    /// Chain of contexts from outermost to innermost.
    public var contextChain: [String] {
        var chain = [context]
        var current: Error = underlying
        while let wrapped = current as? WrappedError {
            chain.append(wrapped.context)
            current = wrapped.underlying
        }
        return chain
    }
}

// MARK: - AppErrorConvertible

nonisolated extension WrappedError: AppErrorConvertible {
    /// Converts this wrapped error to a screen error for UI display.
    ///
    /// Always `ScreenError(title: L10n.error, message: L10n.genericErrorMessage)` — never
    /// `context` and never the `underlying` error's text. See ``message`` for why.
    public var screenError: ScreenError {
        ScreenError(
            title: L10n.error,
            message: message
        )
    }
}

// MARK: - Equatable

/// Compares `context`, `code`, and `underlying.localizedDescription` only.
///
/// Two `WrappedError`s wrapping structurally different `underlying` errors that happen
/// to share a `localizedDescription` compare equal — this is a description-based
/// approximation, not a structural comparison of `underlying` (which isn't `Equatable`
/// as `any Error`). Good enough for tests and simple deduplication; don't rely on it for
/// anything that needs a precise identity check.
nonisolated extension WrappedError: Equatable {
    public static func == (lhs: WrappedError, rhs: WrappedError) -> Bool {
        lhs.context == rhs.context && lhs.code == rhs.code
            && lhs.underlying.localizedDescription == rhs.underlying.localizedDescription
    }
}

// MARK: - CustomDebugStringConvertible

nonisolated extension WrappedError: CustomDebugStringConvertible {
    /// Debug description including the full chain of nested `WrappedError` contexts.
    public var debugDescription: String {
        var desc = description

        // Unwrap nested WrappedErrors
        var current: Error = underlying
        var depth = 1
        while let wrapped = current as? WrappedError {
            desc += "\n  Nested[\(depth)]: \(wrapped.context)"
            current = wrapped.underlying
            depth += 1
        }

        return desc
    }
}

// MARK: - LocalizedError

nonisolated extension WrappedError: LocalizedError {
    /// Same safe, generic text as ``screenError``.
    ///
    /// `Error.localizedDescription` reads this ambiently, without going through
    /// `ErrorPresenting` — any code that calls it directly (a third-party crash reporter, an
    /// OS alert built straight from the error) must see the same safe text `screenError`
    /// shows, not the technical detail. That's the whole point of fixing this here instead of
    /// only in `screenError`.
    public var errorDescription: String? {
        message
    }

    /// `nil`: no additional structured reason beyond ``errorDescription``.
    ///
    /// This used to be `underlying.localizedDescription` — the exact same unvetted text
    /// ``message`` no longer exposes. `failureReason` is meant for display
    /// (`NSError.localizedFailureReason`), so it gets the same treatment rather than a
    /// second, easy-to-miss leak of the same information.
    public var failureReason: String? {
        nil
    }

    /// Forwarded from `underlying` when it opts in by conforming to `LocalizedError` itself.
    ///
    /// Unlike `localizedDescription`, this isn't raw internal text: it's a recovery message
    /// the underlying error's own author deliberately wrote for display. Safe to forward as-is.
    public var recoverySuggestion: String? {
        (underlying as? LocalizedError)?.recoverySuggestion
    }
}

// MARK: - Convenience Extensions

public nonisolated extension Error {
    /// Wraps this error with additional context.
    ///
    /// - Parameters:
    ///   - context: Description of the operation that failed.
    ///   - code: Optional error code for analytics and tracking.
    ///   - file: Call site file (`#fileID`), filled in automatically.
    ///   - line: Call site line (`#line`), filled in automatically.
    /// - Returns: A WrappedError containing this error and the context.
    ///
    /// ## Example
    /// ```swift
    /// do {
    ///     try await fetchData()
    /// } catch {
    ///     throw error.wrapped(context: "Loading profile", code: "PROFILE_001")
    /// }
    /// ```
    func wrapped(
        context: String,
        code: String? = nil,
        file: String = #fileID,
        line: Int = #line
    ) -> WrappedError {
        WrappedError(underlying: self, context: context, code: code, file: file, line: line)
    }
}
