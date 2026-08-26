import Foundation
import Observation

/// Controls how `performLoad` should finish after the async work succeeds.
public nonisolated enum LoadSuccessTransition: Equatable, Sendable {
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
/// - `phase`: what the screen fundamentally is right now (idle / loading / content / empty / error)
/// - `activity`: work that can happen while content stays visible (refresh, submit, sync, pagination)
/// - `alert`: blocking user decision
/// - `banner`: non-blocking feedback (auto-dismisses according to its duration)
///
/// ## Cancellation is part of the contract
///
/// `performLoad` and `performActivity` return their `Task` and retain it: starting a new
/// load cancels the in-flight one, and `deinit` cancels whatever is still running. Work
/// closures should stay cooperative (`Task.checkCancellation()` at progress points) for
/// cancellation to actually interrupt long operations. A cancelled load is never surfaced
/// as a screen error.
@MainActor
@Observable
open class BaseViewModel {
    /// The current screen phase. `.loading` carries how it should be presented.
    public var phase: ViewPhase = .idle

    /// Secondary work that should not replace the current content.
    public var activity: ActivityState = .none

    /// Current alert to display, if any.
    public var alert: AlertState? = nil

    /// Current banner/toast notification to display, if any.
    public var banner: BannerState? = nil

    /// The in-flight primary load, if any. Superseded loads are cancelled.
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// The in-flight secondary activity, if any. Superseded activities are cancelled.
    @ObservationIgnored private var activityTask: Task<Void, Never>?

    /// Pending banner auto-dismiss, if any.
    @ObservationIgnored private var bannerDismissTask: Task<Void, Never>?

    /// Initializes a new base view model.
    public init() {}

    deinit {
        // `Task` is Sendable, so reading these stored properties from the nonisolated
        // deinit is legal — and nothing else can observe the object anymore.
        loadTask?.cancel()
        activityTask?.cancel()
        bannerDismissTask?.cancel()
    }

    // MARK: - Phase Transitions

    /// Transitions the screen to a primary loading phase.
    open func setLoading(_ style: ActivityStyle = .fullScreen) {
        phase = .loading(style)
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

    /// Convenience overload for constructing a `ScreenError` inline (localized resources).
    open func setError(
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        retry: Action? = nil
    ) {
        phase = .error(ScreenError(title: title, message: message, retry: retry))
    }

    /// Runtime-string variant of `setError(title:message:retry:)`.
    @_disfavoredOverload
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
    ///
    /// A banner with `duration: .seconds(n)` auto-dismisses after `n` seconds (A3).
    /// Showing a new banner cancels the previous banner's pending dismissal.
    open func showBanner(_ banner: BannerState) {
        bannerDismissTask?.cancel()
        self.banner = banner

        guard case .seconds(let interval) = banner.duration else { return }
        let bannerID = banner.id
        bannerDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            guard let self, self.banner?.id == bannerID else { return }
            self.banner = nil
        }
    }

    /// Dismisses the current banner and cancels any pending auto-dismiss.
    open func dismissBanner() {
        bannerDismissTask?.cancel()
        bannerDismissTask = nil
        banner = nil
    }

    // MARK: - Async Helpers

    /// Runs a primary load operation.
    ///
    /// Best for initial screen loads where the primary screen phase should switch to
    /// loading. Use `successTransition: .preserveCurrentPhase` when the work decides the
    /// resulting phase itself (e.g. `.empty` vs `.content`).
    ///
    /// Re-entrancy (C8): starting a new load cancels the in-flight one; the superseded
    /// task never mutates screen state after cancellation. Cancellation is not failure —
    /// a cancelled load leaves no error phase behind.
    ///
    /// Errors are converted to `ScreenError` through `AppErrorConvertible` when the
    /// thrown error conforms (A1); `localizedDescription` is only the last-resort
    /// fallback for foreign errors.
    ///
    /// - Returns: The load `Task`. Await it in tests for deterministic sequencing, or
    ///   discard it — the view model retains and manages it either way.
    @discardableResult
    open func performLoad(
        style: ActivityStyle = .fullScreen,
        errorTitle: LocalizedStringResource? = nil,
        successTransition: LoadSuccessTransition = .setContent,
        _ work: @escaping () async throws -> Void
    ) -> Task<Void, Never> {
        loadTask?.cancel()
        setLoading(style)

        let task = Task { [weak self] in
            do {
                try await work()
                guard !Task.isCancelled, let self else { return }
                if successTransition == .setContent {
                    self.setContent()
                }
            } catch is CancellationError {
                // Superseded or torn down: never surface cancellation as an error.
            } catch {
                guard !Task.isCancelled, let self else { return }
                let retry: Action = { [weak self] in
                    self?.performLoad(
                        style: style,
                        errorTitle: errorTitle,
                        successTransition: successTransition,
                        work
                    )
                }
                let fallbackTitle = errorTitle.map { String(localized: $0) } ?? L10n.error
                self.setError(Self.screenError(from: error, fallbackTitle: fallbackTitle, retry: retry))
            }
        }
        loadTask = task
        return task
    }

    /// Runs secondary work while keeping the current screen content visible.
    ///
    /// Ideal for refresh, pagination, form submit, and background sync work. Starting a
    /// new activity cancels the in-flight one; a cancelled activity never mutates state.
    ///
    /// - Returns: The activity `Task`. Await it in tests for deterministic sequencing.
    @discardableResult
    open func performActivity(
        style: ActivityStyle = .overlay,
        errorHandling: ActivityErrorHandling = .banner,
        _ work: @escaping () async throws -> Void
    ) -> Task<Void, Never> {
        activityTask?.cancel()
        startActivity(style)

        let task = Task { [weak self] in
            do {
                try await work()
                guard !Task.isCancelled, let self else { return }
                self.stopActivity()
            } catch is CancellationError {
                // Superseded activity: the newer one owns the state now.
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.stopActivity()
                self.handleActivityError(error, strategy: errorHandling)
            }
        }
        activityTask = task
        return task
    }

    /// Defines how secondary activity errors should be surfaced.
    public nonisolated enum ActivityErrorHandling: Equatable, Sendable {
        /// Show the error as a banner.
        case banner

        /// Show the error as an alert.
        case alert

        /// Ignore the error presentation.
        case silent
    }

    /// Handles the presentation of an error emitted during a secondary activity.
    ///
    /// Consults `AppErrorConvertible` (A1) so domain errors surface their user-facing
    /// message in banners and alerts too.
    open func handleActivityError(_ error: Error, strategy: ActivityErrorHandling) {
        let screenError = Self.screenError(from: error, fallbackTitle: L10n.error, retry: nil)
        switch strategy {
        case .banner:
            showBanner(.error(screenError.message))
        case .alert:
            showAlert(.info(title: screenError.title, message: screenError.message))
        case .silent:
            break
        }
    }

    // MARK: - Error Mapping (A1)

    /// Maps a thrown error to the user-facing `ScreenError`.
    ///
    /// `AppErrorConvertible` (which `WrappedError` adopts) is THE source of user-facing
    /// messages; raw `localizedDescription` is only the fallback for foreign errors.
    nonisolated static func screenError(
        from error: Error,
        fallbackTitle: String,
        retry: Action?
    ) -> ScreenError {
        if let convertible = error as? AppErrorConvertible {
            let base = convertible.screenError
            return ScreenError(title: base.title, message: base.message, retry: retry ?? base.retry)
        }
        return ScreenError(title: fallbackTitle, message: error.localizedDescription, retry: retry)
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
