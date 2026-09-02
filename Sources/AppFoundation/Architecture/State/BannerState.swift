import Foundation

/// Represents a temporary, non-blocking notification (toast/banner).
///
/// `BannerState` is used for ephemeral feedback that doesn't require user interaction,
/// such as success messages, warnings, or info notifications. Unlike `AlertState`,
/// banners automatically dismiss after a duration and don't block user interaction.
///
/// Banners are ideal for:
/// - Confirming successful actions ("Item saved!")
/// - Displaying brief warnings ("Connection unstable")
/// - Showing transient info ("Loading...")
///
/// For errors that require user action or confirmation dialogs, use `AlertState` instead.
///
/// ## Example - Success Notification
/// ```swift
/// let banner = BannerState.success("Profile updated!")
/// showBanner(banner)
/// ```
///
/// ## Example - Error Notification
/// ```swift
/// let banner = BannerState.error("Failed to save changes")
/// showBanner(banner)
/// ```
///
/// ## Example - Custom Duration
/// ```swift
/// let banner = BannerState(
///     message: "Processing request...",
///     style: .info,
///     duration: .seconds(5)        // nil = stays until dismissed
/// )
/// showBanner(banner)
/// ```
public nonisolated struct BannerState: Equatable, Sendable, Identifiable {
    /// Unique identifier for this banner instance.
    public let id: UUID

    /// The message displayed in the banner.
    public let message: String

    /// The visual style (color/appearance) of the banner.
    public let style: Style

    /// How long the banner should remain visible; `nil` keeps it until it is
    /// dismissed programmatically (AF-18: `Swift.Duration`, no shadowing enum).
    public let duration: Swift.Duration?

    /// Creates a new banner state.
    ///
    /// - Parameters:
    ///   - message: Text displayed in the banner
    ///   - style: Visual style (success, info, warning, error)
    ///   - duration: How long to show the banner; `nil` means indefinite
    ///   - id: Unique identifier (auto-generated if not provided)
    public init(
        message: LocalizedStringResource,
        style: Style,
        duration: Swift.Duration?,
        id: UUID = UUID()
    ) {
        self.id = id
        self.message = String(localized: message)
        self.style = style
        self.duration = duration
    }

    /// Runtime-string variant (already-localized text).
    /// Literals prefer the `LocalizedStringResource` initializer (see `ScreenError`).
    @_disfavoredOverload
    public init(
        message: String,
        style: Style,
        duration: Swift.Duration?,
        id: UUID = UUID()
    ) {
        self.id = id
        self.message = message
        self.style = style
        self.duration = duration
    }

    /// Compares two banners by ID.
    public static func == (lhs: BannerState, rhs: BannerState) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Factory Methods

    /// Creates a success notification banner.
    ///
    /// - Parameter message: Text displayed in the banner
    /// - Returns: A new `BannerState` configured for success feedback
    public static func success(_ message: LocalizedStringResource) -> BannerState {
        BannerState(message: message, style: .success, duration: .seconds(3))
    }

    /// Runtime-string variant of `success(_:)`.
    @_disfavoredOverload
    public static func success(_ message: String) -> BannerState {
        BannerState(message: message, style: .success, duration: .seconds(3))
    }

    /// Creates an error notification banner.
    ///
    /// - Parameter message: Text displayed in the banner
    /// - Returns: A new `BannerState` configured for error feedback
    public static func error(_ message: LocalizedStringResource) -> BannerState {
        BannerState(message: message, style: .error, duration: .seconds(4))
    }

    /// Runtime-string variant of `error(_:)`.
    @_disfavoredOverload
    public static func error(_ message: String) -> BannerState {
        BannerState(message: message, style: .error, duration: .seconds(4))
    }

    /// Creates an informational notification banner.
    ///
    /// - Parameter message: Text displayed in the banner
    /// - Returns: A new `BannerState` configured for informational feedback
    public static func info(_ message: LocalizedStringResource) -> BannerState {
        BannerState(message: message, style: .info, duration: .seconds(3))
    }

    /// Runtime-string variant of `info(_:)`.
    @_disfavoredOverload
    public static func info(_ message: String) -> BannerState {
        BannerState(message: message, style: .info, duration: .seconds(3))
    }

    /// Creates a warning notification banner.
    ///
    /// - Parameter message: Text displayed in the banner
    /// - Returns: A new `BannerState` configured for warning feedback
    public static func warning(_ message: LocalizedStringResource) -> BannerState {
        BannerState(message: message, style: .warning, duration: .seconds(4))
    }

    /// Runtime-string variant of `warning(_:)`.
    @_disfavoredOverload
    public static func warning(_ message: String) -> BannerState {
        BannerState(message: message, style: .warning, duration: .seconds(4))
    }

    /// The visual style of a banner.
    public enum Style: Equatable, Sendable {
        /// Success style (typically green).
        case success

        /// Informational style (typically blue).
        case info

        /// Warning style (typically yellow/orange).
        case warning

        /// Error style (typically red).
        case error
    }
}
