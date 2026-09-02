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
/// ## `performLoad`/`performActivity` never capture `self`
///
/// The `work` closure is declared on `LoadableViewModel` (which `BaseViewModel` conforms
/// to) and receives the view model as a parameter instead of relying on closure capture:
///
/// ```swift
/// performLoad { vm in
///     vm.items = try await vm.repository.fetch()
/// }
/// ```
///
/// This is what makes cancellation and deallocation actually work (see below) — not a
/// convention to remember, a shape the API forces.
///
/// ## Cancellation is part of the contract
///
/// `performLoad` and `performActivity` return their `Task` and retain it: starting a new
/// load cancels the in-flight one, and `deinit` cancels whatever is still running — and
/// because `work` never captures the view model, releasing the last external reference
/// while a load is in flight (or while it's showing a retryable error) actually
/// deallocates it, which is what lets `deinit` run and cancel the work in the first
/// place. Work closures should stay cooperative (`Task.checkCancellation()` at progress
/// points) for cancellation to actually interrupt long operations. A cancelled load —
/// or any error `cancellationRecognizer` recognizes as cancellation — is never surfaced
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

    /// The in-flight primary load `Task`, if any — read-only from outside the class.
    /// Starting a new load cancels and replaces this; it is set back to `nil` once the
    /// load finishes (success, failure, or cancellation), unless a newer load has already
    /// replaced it by then.
    ///
    /// Await it in tests instead of polling `phase`/`hasError` — including after
    /// `handle(_:)`, which returns `Void` and can't hand back the `Task` itself:
    ///
    /// ```swift
    /// viewModel.handle(.load)
    /// await viewModel.inFlightLoad?.value
    /// #expect(viewModel.phase == .content)
    /// ```
    @ObservationIgnored public private(set) var inFlightLoad: Task<Void, Never>?

    /// The in-flight secondary activity `Task`, if any. Same contract as `inFlightLoad`,
    /// for `performActivity`/`activity(_:)` instead of `performLoad`/`load(_:)`.
    @ObservationIgnored public private(set) var inFlightActivity: Task<Void, Never>?

    /// Bumped on every `_performLoad` call; lets a completing load recognize it has since
    /// been superseded so it doesn't clear a newer `inFlightLoad`.
    @ObservationIgnored private var loadGeneration = 0

    /// Same role as `loadGeneration`, for `inFlightActivity`.
    @ObservationIgnored private var activityGeneration = 0

    /// Pending banner auto-dismiss, if any.
    @ObservationIgnored private var bannerDismissTask: Task<Void, Never>?

    /// Per-instance error presenter override. `nil` defers to `BaseViewModel.errorPresenter`.
    @ObservationIgnored private let instanceErrorPresenter: (any ErrorPresenting)?

    /// Per-instance cancellation recognizer override. `nil` defers to
    /// `BaseViewModel.cancellationRecognizer`.
    @ObservationIgnored private let instanceCancellationRecognizer: (any CancellationRecognizing)?

    /// Per-instance clock override. `nil` defers to `BaseViewModel.clock`.
    @ObservationIgnored private let instanceClock: (any Clock<Duration>)?

    /// The error presenter used by every `BaseViewModel` instance that doesn't override
    /// one through its initializer. Configure this once at app startup:
    ///
    /// ```swift
    /// BaseViewModel.errorPresenter = AppErrorPresenter()
    /// ```
    ///
    /// Defaults to `DefaultErrorPresenter()`.
    public static var errorPresenter: any ErrorPresenting = DefaultErrorPresenter()

    /// Recognizes cancellation beyond typed `CancellationError` (e.g. `URLError(.cancelled)`,
    /// or an app's own network error type), for every `BaseViewModel` instance that doesn't
    /// override one through its initializer. Extend it at app startup:
    ///
    /// ```swift
    /// BaseViewModel.cancellationRecognizer = AppCancellationRecognizer()
    /// ```
    ///
    /// Defaults to `DefaultCancellationRecognizer()`.
    public static var cancellationRecognizer: any CancellationRecognizing = DefaultCancellationRecognizer()

    /// The clock used to schedule a banner's auto-dismiss, for every `BaseViewModel`
    /// instance that doesn't override one through its initializer. Tests inject a manual
    /// clock through the initializer instead of mutating this (see `init`) — a `static var`
    /// mutated by one test is visible to every other test running in parallel. Defaults to
    /// `ContinuousClock()`.
    public static var clock: any Clock<Duration> = ContinuousClock()

    /// Initializes a new base view model.
    ///
    /// - Parameters:
    ///   - errorPresenter: Overrides `BaseViewModel.errorPresenter` for this instance only.
    ///     Most view models don't need this — set the static instead.
    ///   - cancellationRecognizer: Overrides `BaseViewModel.cancellationRecognizer` for this
    ///     instance only.
    ///   - clock: Overrides `BaseViewModel.clock` for this instance only. Tests inject a
    ///     manual clock here to control a banner's auto-dismiss deterministically, instead
    ///     of mutating the `static var` (DC-AF-3): an instance override can't leak into a
    ///     different test running in parallel.
    public init(
        errorPresenter: (any ErrorPresenting)? = nil,
        cancellationRecognizer: (any CancellationRecognizing)? = nil,
        clock: (any Clock<Duration>)? = nil
    ) {
        self.instanceErrorPresenter = errorPresenter
        self.instanceCancellationRecognizer = cancellationRecognizer
        self.instanceClock = clock
    }

    deinit {
        // `Task` is Sendable, so reading these stored properties from the nonisolated
        // deinit is legal — and nothing else can observe the object anymore.
        inFlightLoad?.cancel()
        inFlightActivity?.cancel()
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
    /// A banner with a `duration` auto-dismisses after it elapses; `nil` stays (A3). The
    /// wait is scheduled through `BaseViewModel.clock` (injectable; tests never sleep for
    /// real). Showing a new banner cancels the previous banner's pending dismissal.
    open func showBanner(_ banner: BannerState) {
        bannerDismissTask?.cancel()
        self.banner = banner

        guard let duration = banner.duration else { return }
        let bannerID = banner.id
        let clock = effectiveClock
        bannerDismissTask = Task { [weak self] in
            try? await clock.sleep(for: duration)
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

    // MARK: - Async Helpers (internal engine — see `LoadableViewModel` for the public API)

    /// Runs an unstructured load: owns and retains its `Task`, cancels a superseded one,
    /// and hands the error path a pre-built retry action.
    ///
    /// `work` and `retry` are built by `LoadableViewModel.performLoad`, which is the only
    /// caller — by the time they reach here, neither captures the view model strongly.
    @discardableResult
    func _performLoad(
        style: ActivityStyle,
        errorTitle: LocalizedStringResource?,
        successTransition: LoadSuccessTransition,
        retry: @escaping Action,
        _ work: @escaping @MainActor () async throws -> Void
    ) -> Task<Void, Never> {
        inFlightLoad?.cancel()
        setLoading(style)

        loadGeneration &+= 1
        let generation = loadGeneration

        let task = Task { [weak self] in
            guard let self else { return }
            await self._runLoad(
                style: style,
                errorTitle: errorTitle,
                successTransition: successTransition,
                retry: retry,
                work
            )
            // Only clear `inFlightLoad` if no newer load has replaced it in the meantime —
            // otherwise this completing (superseded) task would clobber the current one.
            if self.loadGeneration == generation {
                self.inFlightLoad = nil
            }
        }
        inFlightLoad = task
        return task
    }

    /// The load body shared by the unstructured (`Task`-owning) and structured (`async`)
    /// entry points. Assumes `phase` is already `.loading` when it starts.
    func _runLoad(
        style: ActivityStyle,
        errorTitle: LocalizedStringResource?,
        successTransition: LoadSuccessTransition,
        retry: Action?,
        _ work: @escaping @MainActor () async throws -> Void
    ) async {
        do {
            try await work()
            guard !Task.isCancelled else { return }
            if successTransition == .setContent {
                setContent()
            }
        } catch {
            guard !Task.isCancelled, !recognizer.isCancellation(error) else { return }
            let fallbackTitle = errorTitle.map { String(localized: $0) } ?? L10n.error
            setError(presenter.screenError(for: error, fallbackTitle: fallbackTitle, retry: retry))
        }
    }

    /// Runs an unstructured activity: owns and retains its `Task`, cancels a superseded one.
    @discardableResult
    func _performActivity(
        style: ActivityStyle,
        errorHandling: ActivityErrorHandling,
        _ work: @escaping @MainActor () async throws -> Void
    ) -> Task<Void, Never> {
        inFlightActivity?.cancel()
        startActivity(style)

        activityGeneration &+= 1
        let generation = activityGeneration

        let task = Task { [weak self] in
            guard let self else { return }
            await self._runActivity(style: style, errorHandling: errorHandling, work)
            // Same non-clobbering guard as `_performLoad`'s.
            if self.activityGeneration == generation {
                self.inFlightActivity = nil
            }
        }
        inFlightActivity = task
        return task
    }

    /// The activity body shared by the unstructured and structured entry points. Assumes
    /// `activity` is already `.loading` when it starts.
    func _runActivity(
        style: ActivityStyle,
        errorHandling: ActivityErrorHandling,
        _ work: @escaping @MainActor () async throws -> Void
    ) async {
        do {
            try await work()
            guard !Task.isCancelled else { return }
            stopActivity()
        } catch {
            guard !Task.isCancelled, !recognizer.isCancellation(error) else { return }
            stopActivity()
            handleActivityError(error, strategy: errorHandling)
        }
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
    /// Consults `errorPresenter` so domain errors surface their user-facing message in
    /// banners and alerts too, exactly like `performLoad`.
    open func handleActivityError(_ error: Error, strategy: ActivityErrorHandling) {
        let screenError = presenter.screenError(for: error, fallbackTitle: L10n.error, retry: nil)
        switch strategy {
        case .banner:
            showBanner(.error(screenError.message))
        case .alert:
            showAlert(.info(title: screenError.title, message: screenError.message))
        case .silent:
            break
        }
    }

    // MARK: - Error Mapping

    /// The effective error presenter for this instance: the per-instance override, then
    /// `BaseViewModel.errorPresenter` (which is `DefaultErrorPresenter()` unless the app
    /// replaced it).
    private var presenter: any ErrorPresenting {
        instanceErrorPresenter ?? Self.errorPresenter
    }

    /// The effective cancellation recognizer for this instance: the per-instance override,
    /// then `BaseViewModel.cancellationRecognizer`. Same precedence as `presenter`.
    private var recognizer: any CancellationRecognizing {
        instanceCancellationRecognizer ?? Self.cancellationRecognizer
    }

    /// The effective clock for this instance: the per-instance override, then
    /// `BaseViewModel.clock`. Same precedence as `presenter`.
    private var effectiveClock: any Clock<Duration> {
        instanceClock ?? Self.clock
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
