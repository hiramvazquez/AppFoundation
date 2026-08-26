import Foundation

/// Represents an alert dialog that requires user interaction.
///
/// `AlertState` replaces the old generic alert system with a concrete, easy-to-use model.
/// It supports both single-button (dismiss) and two-button (confirm/cancel) patterns.
///
/// Alerts are blocking; they prevent interaction with the content behind them and require
/// user action to dismiss. For non-blocking notifications, use `BannerState` instead.
///
/// ## Equatable Behavior
/// Two alerts are equal if their IDs match. This allows the view to track alert state
/// changes and dismiss alerts when the state is set to `nil`.
///
/// ## Example - Simple Dismissal Alert
/// ```swift
/// let alert = AlertState.info(
///     title: "Welcome",
///     message: "Thanks for using our app!",
///     dismiss: { print("Dismissed") }
/// )
/// showAlert(alert)
/// ```
///
/// ## Example - Confirmation Alert
/// ```swift
/// let alert = AlertState.confirmation(
///     title: "Delete Item?",
///     message: "This action cannot be undone.",
///     confirm: "Delete",
///     cancel: "Cancel",
///     onConfirm: { [weak self] in self?.deleteItem() }
/// )
/// showAlert(alert)
/// ```
///
/// ## Example - Destructive Action Alert
/// ```swift
/// let alert = AlertState.destructive(
///     title: "Sign Out?",
///     message: "You will be signed out of your account.",
///     confirm: "Sign Out",
///     cancel: "Cancel",
///     onConfirm: { [weak self] in self?.signOut() }
/// )
/// showAlert(alert)
/// ```
public nonisolated struct AlertState: Equatable, Sendable, Identifiable {
    /// Unique identifier for this alert instance.
    ///
    /// Used to track and dismiss alerts in the UI.
    public let id: UUID

    /// The title displayed at the top of the alert dialog.
    public let title: String

    /// The detailed message shown in the alert body.
    public let message: String

    /// The primary button (confirm/accept action).
    public let primaryButton: Button

    /// Optional secondary button (usually cancel).
    public let secondaryButton: Button?

    /// Creates a new alert state.
    ///
    /// - Parameters:
    ///   - title: Title displayed at the top
    ///   - message: Detailed message in the body
    ///   - primaryButton: The primary action button
    ///   - secondaryButton: Optional secondary action button
    ///   - id: Unique identifier (auto-generated if not provided)
    public init(
        title: String,
        message: String,
        primaryButton: Button,
        secondaryButton: Button? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.primaryButton = primaryButton
        self.secondaryButton = secondaryButton
    }

    /// Compares two alerts by ID.
    public static func == (lhs: AlertState, rhs: AlertState) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Factory Methods

    /// Creates an informational alert with a single dismiss button.
    ///
    /// Use this for notifications that don't require a decision from the user.
    ///
    /// - Parameters:
    ///   - title: Alert title
    ///   - message: Alert message
    ///   - dismiss: Action to execute when dismissed
    /// - Returns: A new `AlertState` configured for informational purposes
    public static func info(
        title: String,
        message: String,
        dismiss: @escaping Action = {}
    ) -> AlertState {
        AlertState(
            title: title,
            message: message,
            primaryButton: Button(title: "OK", role: .default, action: dismiss)
        )
    }

    /// Creates a confirmation alert with two buttons.
    ///
    /// Use this when the user must confirm before an action proceeds.
    ///
    /// - Parameters:
    ///   - title: Alert title
    ///   - message: Alert message
    ///   - confirm: Title for the confirm button
    ///   - cancel: Title for the cancel button
    ///   - onConfirm: Action to execute if confirmed
    /// - Returns: A new `AlertState` configured for confirmation
    public static func confirmation(
        title: String,
        message: String,
        confirm: String,
        cancel: String,
        onConfirm: @escaping Action
    ) -> AlertState {
        AlertState(
            title: title,
            message: message,
            primaryButton: Button(title: confirm, role: .default, action: onConfirm),
            secondaryButton: Button(title: cancel, role: .cancel, action: {})
        )
    }

    /// Creates a destructive action alert.
    ///
    /// Use this for actions that cannot be undone (e.g., delete, sign out).
    /// The confirm button is styled as destructive (usually red).
    ///
    /// - Parameters:
    ///   - title: Alert title
    ///   - message: Alert message
    ///   - confirm: Title for the destructive button
    ///   - cancel: Title for the cancel button
    ///   - onConfirm: Action to execute if confirmed
    /// - Returns: A new `AlertState` configured for destructive actions
    public static func destructive(
        title: String,
        message: String,
        confirm: String,
        cancel: String,
        onConfirm: @escaping Action
    ) -> AlertState {
        AlertState(
            title: title,
            message: message,
            primaryButton: Button(title: confirm, role: .destructive, action: onConfirm),
            secondaryButton: Button(title: cancel, role: .cancel, action: {})
        )
    }

    /// Represents a button within an alert dialog.
    public struct Button: Equatable, Sendable {
        /// The text displayed on the button.
        public let title: String

        /// The semantic role of the button (affects styling and default behaviors).
        public let role: Role

        /// Action executed when the button is tapped.
        public let action: Action

        /// Creates a new alert button.
        ///
        /// - Parameters:
        ///   - title: Text displayed on the button
        ///   - role: Semantic role (default, cancel, destructive)
        ///   - action: Action executed when tapped
        public init(
            title: String,
            role: Role,
            action: @escaping Action
        ) {
            self.title = title
            self.role = role
            self.action = action
        }

        /// The semantic role of a button.
        public enum Role: Equatable, Sendable {
            /// Default action button (typically blue or accent color).
            case `default`

            /// Cancel button (typically gray or neutral color).
            case cancel

            /// Destructive action (typically red, warning color).
            case destructive
        }

        /// Buttons are equal if their title and role match.
        /// The action closure is ignored to allow state comparison.
        public static func == (lhs: Button, rhs: Button) -> Bool {
            lhs.title == rhs.title && lhs.role == rhs.role
        }
    }
}
