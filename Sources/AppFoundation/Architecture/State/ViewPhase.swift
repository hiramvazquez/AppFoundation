import Foundation

/// Represents the current phase of a view's lifecycle and data loading state.
///
/// `ViewPhase` replaces the old generic `ViewState<Alert, Error>` with a simpler,
/// non-generic model that's easier to use and reason about. All errors are
/// represented as `ScreenError` and all UI feedback goes through the ViewModel.
///
/// ## States
/// - **idle**: Initial state, no operation in progress
/// - **loading**: Data is being fetched or processed
/// - **content**: Data is available and ready to display
/// - **empty**: Operation succeeded but returned no data
/// - **error**: An error occurred; use the retry action to recover
///
/// ## Example
/// ```swift
/// @Published var phase: ViewPhase = .idle
///
/// func loadData() async {
///     phase = .loading
///     do {
///         let data = try await fetchData()
///         if data.isEmpty {
///             phase = .empty
///         } else {
///             phase = .content
///         }
///     } catch {
///         phase = .error(
///             ScreenError(
///                 title: "Failed to Load",
///                 message: error.localizedDescription,
///                 retry: { [weak self] in Task { await self?.loadData() } }
///            )
///         )
///     }
/// }
/// ```
public enum ViewPhase: Equatable, Sendable {
    /// Initial state; no loading in progress.
    case idle

    /// Data is being loaded or an operation is in progress.
    case loading

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
public struct ScreenError: Equatable, Sendable {
    /// The title displayed at the top of the error screen.
    public let title: String

    /// The detailed message explaining what went wrong.
    public let message: String

    /// Optional action to retry the failed operation.
    ///
    /// If provided, a retry button is shown to the user.
    public let retry: Action?

    /// Creates a new screen error.
    ///
    /// - Parameters:
    ///   - title: Title displayed at the top of the error screen
    ///   - message: Detailed message explaining the error
    ///   - retry: Optional action to retry the failed operation
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

/// Defines how a loading indicator should be presented to the user.
///
/// Used to control the appearance and behavior of loading UI during asynchronous operations.
///
/// ## Styles
/// - **fullScreen**: Loading overlay covers the entire screen (opaque or semi-transparent)
/// - **inline**: Loading indicator embedded within the content area
/// - **overlay**: Semi-transparent overlay with spinner; allows user interaction below
///
/// ## Example
/// ```swift
/// // Show a full-screen spinner during initial load
/// func loadData() {
///     setLoading(.fullScreen)
///     // ...
/// }
///
/// // Show inline spinner during pagination
/// func loadMore() {
///     setLoading(.inline)
///     // ...
/// }
/// ```
public enum LoadingStyle: Equatable, Sendable {
    /// Loading overlay covers the entire screen and blocks interaction.
    case fullScreen

    /// Loading indicator is embedded inline within the content area.
    case inline

    /// Semi-transparent overlay with spinner; allows interaction with content below.
    case overlay
}
