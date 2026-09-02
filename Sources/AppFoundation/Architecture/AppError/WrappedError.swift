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

    /// User-friendly error message combining context and underlying error.
    public var message: String {
        "\(context): \(underlying.localizedDescription)"
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
    public var errorDescription: String? {
        message
    }

    public var failureReason: String? {
        underlying.localizedDescription
    }

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
