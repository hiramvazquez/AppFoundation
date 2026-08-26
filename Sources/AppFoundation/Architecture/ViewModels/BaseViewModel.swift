import Combine

/// Controls how `performLoad` should finish after the async work succeeds.
public enum LoadSuccessTransition: Equatable, Sendable {
    /// Transition to `.content` automatically.
    case setContent

    /// Preserve whatever phase the work set explicitly.
    case preserveCurrentPhase
}

/// Base class for view models managing screen phase, secondary activity, alerts, and banners.
///
/// `BaseViewModel` is intentionally concrete and pragmatic. It gives most screens a shared,
/// low-friction foundation without forcing a heavyweight state machine. The main screen is
/// modelled through `phase`, while transient background work that should not replace visible
/// content is modelled through `activity`.
///
/// Use this split as a rule of thumb:
/// - `phase`: controls what the screen fundamentally is right now (idle / loading / content / empty / error)
/// - `activity`: work that can happen while content stays visible (refresh, submit, sync, pagination)
/// - `alert`: blocking user decision
/// - `banner`: non-blocking feedback
@MainActor
open class BaseViewModel: ObservableObject {
    /// The current screen phase.
    @Published public var phase: ViewPhase = .idle

    /// How the primary loading phase should be displayed.
    @Published public var loadingStyle: LoadingStyle = .fullScreen

    /// Secondary work that should not replace the current content.
    @Published public var activity: ActivityState = .none

    /// Current alert to display, if any.
    @Published public var alert: AlertState? = nil

    /// Current banner/toast notification to display, if any.
    @Published public var banner: BannerState? = nil

    /// Initializes a new base view model.
    public init() {}

    // MARK: - Phase Transitions

    /// Transitions the screen to a primary loading phase.
    open func setLoading(_ style: LoadingStyle = .fullScreen) {
        loadingStyle = style
        phase = .loading
    }

    /// Transitions the screen to the content phase.
    open func setContent() {
        phase = .content
    }

    /// Transitions the screen to the empty phase.
    open func setEmpty() {
        phase = .empty
    }

    /// Transitions the screen to an error phase.
    open func setError(_ error: ScreenError) {
        phase = .error(error)
    }

    /// Convenience overload for constructing a `ScreenError` inline.
    open func setError(
        title: String,
        message: String,
        retry: Action? = nil
    ) {
        phase = .error(ScreenError(title: title, message: message, retry: retry))
    }

    /// Resets the screen to idle.
    open func setIdle() {
        phase = .idle
    }

    // MARK: - Secondary Activity

    /// Starts a secondary activity while leaving the current screen content in place.
    open func startActivity(_ style: ActivityStyle = .overlay) {
        activity = .loading(style)
    }

    /// Stops any active secondary activity.
    open func stopActivity() {
        activity = .none
    }

    // MARK: - Alert Management

    /// Displays an alert.
    open func showAlert(_ alert: AlertState) {
        self.alert = alert
    }

    /// Dismisses the current alert.
    open func dismissAlert() {
        alert = nil
    }

    // MARK: - Banner Management

    /// Displays a non-blocking banner.
    open func showBanner(_ banner: BannerState) {
        self.banner = banner
    }

    /// Dismisses the current banner.
    open func dismissBanner() {
        banner = nil
    }

    // MARK: - Async Helpers

    /// Runs a primary load operation.
    ///
    /// This is best for initial screen loads where the primary screen phase should switch to loading.
    /// Use `successTransition: .preserveCurrentPhase` when the work decides the resulting phase itself.
    open func performLoad(
        style: LoadingStyle = .fullScreen,
        errorTitle: String = "Error",
        successTransition: LoadSuccessTransition = .setContent,
        _ work: @escaping () async throws -> Void
    ) {
        setLoading(style)

        Task {
            do {
                try await work()
                if successTransition == .setContent {
                    setContent()
                }
            } catch {
                setError(
                    title: errorTitle,
                    message: error.localizedDescription,
                    retry: { [weak self] in
                        self?.performLoad(
                            style: style,
                            errorTitle: errorTitle,
                            successTransition: successTransition,
                            work
                        )
                    }
                )
            }
        }
    }

    /// Backwards-compatible convenience wrapper for the old API.
    open func load(
        style: LoadingStyle = .fullScreen,
        errorTitle: String = "Error",
        _ work: @escaping () async throws -> Void
    ) {
        performLoad(style: style, errorTitle: errorTitle, successTransition: .setContent, work)
    }

    /// Runs secondary work while keeping the current screen content visible.
    ///
    /// This is ideal for refresh, pagination, form submit, and background sync work.
    open func performActivity(
        style: ActivityStyle = .overlay,
        errorHandling: ActivityErrorHandling = .banner,
        _ work: @escaping () async throws -> Void
    ) {
        startActivity(style)

        Task {
            do {
                try await work()
                stopActivity()
            } catch {
                stopActivity()
                handleActivityError(error, strategy: errorHandling)
            }
        }
    }

    /// Defines how secondary activity errors should be surfaced.
    public enum ActivityErrorHandling: Equatable, Sendable {
        /// Show the error as a banner.
        case banner

        /// Show the error as an alert.
        case alert

        /// Ignore the error presentation.
        case silent
    }

    /// Handles the presentation of an error emitted during a secondary activity.
    open func handleActivityError(_ error: Error, strategy: ActivityErrorHandling) {
        switch strategy {
        case .banner:
            showBanner(.error(error.localizedDescription))
        case .alert:
            showAlert(.info(title: "Error", message: error.localizedDescription))
        case .silent:
            break
        }
    }

    // MARK: - Computed Helpers

    public var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    public var isContent: Bool {
        if case .content = phase { return true }
        return false
    }

    public var isEmpty: Bool {
        if case .empty = phase { return true }
        return false
    }

    public var hasError: Bool {
        if case .error = phase { return true }
        return false
    }

    public var isIdle: Bool {
        if case .idle = phase { return true }
        return false
    }

    public var currentError: ScreenError? {
        if case .error(let error) = phase { return error }
        return nil
    }

    public var isPerformingActivity: Bool {
        if case .loading = activity { return true }
        return false
    }
}
