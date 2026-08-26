import Foundation

/// Represents the current phase of a view's lifecycle and data loading state.
///
/// All errors are represented as `ScreenError` and all UI feedback goes through the
/// ViewModel. The `.loading` phase carries its own `ActivityStyle` — there is ONE
/// activity presentation system shared by the primary phase and secondary activity.
///
/// ## States
/// - **idle**: Initial state, no operation in progress
/// - **loading(style)**: Data is being fetched; `style` says how to present it
/// - **content**: Data is available and ready to display
/// - **empty**: Operation succeeded but returned no data
/// - **error**: An error occurred; use the retry action to recover
///
/// ## Example
/// ```swift
/// func loadData() {
///     performLoad {
///         let data = try await repository.fetch()
///         if data.isEmpty { self.setEmpty() }
///     }
/// }
/// ```
public nonisolated enum ViewPhase: Equatable, Sendable {
    /// Initial state; no loading in progress.
    case idle

    /// Data is being loaded or an operation is in progress, presented with the given style.
    case loading(ActivityStyle)

    /// Data is available and ready to display.
    case content

    /// Operation succeeded but returned no data to display.
    case empty

    /// An error occurred during the operation.
    ///
    /// Contains a `ScreenError` with title, message, and optional retry action.
    case error(ScreenError)
}

/// Represents an error condition with user-facing messaging and recovery options.
///
/// `ScreenError` provides the information needed to display an error screen to the user,
/// including a title, message, and an optional action to retry the failed operation.
///
/// ## Equatable Behavior
/// Two `ScreenError` instances are equal if their `title` and `message` are equal.
/// The `retry` closure is ignored in equality comparisons to allow state comparison
/// without worrying about closure differences.
///
/// ## Example
/// ```swift
/// let error = ScreenError(
///     title: "Network Error",
///     message: "Unable to connect to the server. Please check your connection.",
///     retry: { [weak self] in Task { await self?.loadData() } }
/// )
/// ```
public nonisolated struct ScreenError: Equatable, Sendable {
    /// The title displayed at the top of the error screen.
    public let title: String

    /// The detailed message explaining what went wrong.
    public let message: String

    /// Optional action to retry the failed operation.
    ///
    /// If provided, a retry button is shown to the user.
    public let retry: Action?

    /// Creates a new screen error from localized resources (A13).
    ///
    /// String literals localize through the app's catalog (`ScreenError(title: "error_title", ...)`
    /// looks "error_title" up in the main bundle and falls back to the literal).
    ///
    /// - Parameters:
    ///   - title: Title displayed at the top of the error screen
    ///   - message: Detailed message explaining the error
    ///   - retry: Optional action to retry the failed operation
    public init(
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        retry: Action? = nil
    ) {
        self.title = String(localized: title)
        self.message = String(localized: message)
        self.retry = retry
    }

    /// Creates a screen error from already-localized runtime strings
    /// (e.g. a backend message or `error.localizedDescription`).
    ///
    /// `@_disfavoredOverload` (the same technique SwiftUI's `Text` uses): string
    /// LITERALS prefer the `LocalizedStringResource` initializer and localize; only
    /// runtime `String` values land here, stored verbatim.
    @_disfavoredOverload
    public init(
        title: String,
        message: String,
        retry: Action? = nil
    ) {
        self.title = title
        self.message = message
        self.retry = retry
    }

    /// Compares two errors by their title and message, ignoring the retry closure.
    public static func == (lhs: ScreenError, rhs: ScreenError) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message
    }
}

