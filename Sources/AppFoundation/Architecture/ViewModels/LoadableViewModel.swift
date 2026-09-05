import Foundation

/// Adds `performLoad`/`performActivity`/`load`/`activity` to `BaseViewModel` subclasses.
///
/// The protocol exists so the `work` closure can receive the view model as a typed
/// parameter (`Self`) instead of capturing it — classes can't declare a method parameter
/// of covariant `Self`, but a protocol extension can. `BaseViewModel` itself conforms
/// (see the extension below), so every subclass gets `Self` resolved to its own concrete
/// type automatically; no subclass needs to declare conformance itself.
///
/// ```swift
/// final class ProfileViewModel: BaseViewModel {
///     private(set) var profile: Profile?
///     private let repository: ProfileRepository
///
///     func load() {
///         performLoad { vm in
///             vm.profile = try await vm.repository.fetch()
///         }
///     }
/// }
/// ```
///
/// `work` never captures the view model: `vm` is handed in, so nothing in the closure
/// keeps `self` alive. That closes off a *permanent* retain cycle by construction — the
/// classic failure where a screen stuck on `.error` keeps its view model alive forever
/// through a captured `retry` action. It does not mean the view model deallocates the
/// instant the last external reference drops: `work` still needs the view model to run,
/// so the `Task` running it holds the view model strongly for as long as `work` is
/// suspended. See `BaseViewModel`'s "What `deinit` actually cancels" for the exact
/// contract, and `load(_:)`/`activity(_:)` below for the API that ties cancellation to the
/// view's lifecycle instead of to deallocation.
public protocol LoadableViewModel: BaseViewModel {}

extension BaseViewModel: LoadableViewModel {}

extension LoadableViewModel {
    /// Runs a load in the caller's own `Task` — the default choice for a screen's initial
    /// content, and for any load whose lifetime should match the caller's.
    ///
    /// Call it directly from `.task`, which is `async` and can `await` it — unlike
    /// `ActionHandling.handle(_:)`, which is synchronous by design and can't:
    ///
    /// ```swift
    /// .task {
    ///     await viewModel.load { vm in
    ///         vm.items = try await vm.service.fetch()
    ///     }
    /// }
    /// ```
    ///
    /// SwiftUI cancels the view's `.task` the moment the view disappears, so cancellation
    /// follows the view exactly — the work is actually torn down, not just abandoned to
    /// finish on its own. Use `successTransition: .preserveCurrentPhase` when `work`
    /// decides the resulting phase itself (e.g. `.empty` vs `.content`). On failure,
    /// `work` is retried — unchanged — through `performLoad`, so a retry survives even if
    /// the view that started the original `load(_:)` is long gone by then.
    ///
    /// Reach for `performLoad` below instead when the call site can't `await` (most
    /// commonly because it's routed through `handle(_:)` alongside a screen's other
    /// actions) or when the work must outlive the view on purpose — a submit that
    /// shouldn't cancel just because the user navigated away.
    public func load(
        style: ActivityStyle = .fullScreen,
        errorTitle: LocalizedStringResource? = nil,
        successTransition: LoadSuccessTransition = .setContent,
        _ work: @escaping @MainActor (Self) async throws -> Void
    ) async {
        let retry: Action = { [weak self] in
            guard let self else { return }
            self.performLoad(
                style: style,
                errorTitle: errorTitle,
                successTransition: successTransition,
                work
            )
        }
        setLoading(style)
        await _runLoad(style: style, errorTitle: errorTitle, successTransition: successTransition, retry: retry) {
            try await work(self)
        }
    }

    /// Runs secondary work in the caller's own `Task`. See `load(_:)` above for when to
    /// prefer this over `performActivity`.
    ///
    /// Same phase transitions and error handling as `performActivity`; same
    /// tied-to-the-caller cancellation as `load(_:)`.
    public func activity(
        style: ActivityStyle = .overlay,
        errorHandling: BaseViewModel.ActivityErrorHandling = .banner,
        _ work: @escaping @MainActor (Self) async throws -> Void
    ) async {
        startActivity(style)
        await _runActivity(style: style, errorHandling: errorHandling) {
            try await work(self)
        }
    }

    /// Runs an unstructured load: owns and retains its own `Task`, independent of the
    /// caller's, switching `phase` to `.loading` immediately.
    ///
    /// The exception to `load(_:)` above: reach for this when the call site can't `await`
    /// — typically because it's wired through `ActionHandling.handle(_:)`, which is
    /// synchronous by design, often alongside a screen's other actions for a single point
    /// of entry — or when the work must survive the view on purpose. Use
    /// `successTransition: .preserveCurrentPhase` when `work` decides the resulting phase
    /// itself (e.g. `.empty` vs `.content`).
    ///
    /// Starting a new load cancels the in-flight one (re-entrancy); the superseded task
    /// never mutates screen state after cancellation. A cancelled load never becomes a
    /// screen error — neither does any error `BaseViewModel.cancellationRecognizer`
    /// recognizes as cancellation.
    ///
    /// On failure, `work` is retried, unchanged, through the `ScreenError.retry` action —
    /// which is why `work` must not capture `self`: the retry closure only captures the
    /// view model weakly, so a rejected screen releases cleanly. While a load is actually
    /// running, though, `work` needs the view model to make any progress, so the `Task`
    /// running it holds the view model strongly for the duration — releasing the last
    /// external reference then does not deallocate it, and `deinit` cannot cancel that
    /// `Task` until `work` itself returns. See `BaseViewModel`'s "What `deinit` actually
    /// cancels" for the full contract; use `load(_:)` above instead when the load should
    /// be torn down the moment the view goes away.
    ///
    /// If the view model is deallocated before `work` gets to run (its `Task` holds the
    /// view model weakly until then), the work is skipped as a cancellation — no error
    /// reaches the screen — and, in `DEBUG` builds, the skip is logged at `.error` level
    /// and reported through ``AppFoundationDiagnostics``: the usual cause is a View
    /// holding its view model with `let` instead of `@State`.
    ///
    /// - Returns: The load `Task`. Await it in tests for deterministic sequencing, or
    ///   discard it — the view model retains and manages it either way.
    @discardableResult
    public func performLoad(
        style: ActivityStyle = .fullScreen,
        errorTitle: LocalizedStringResource? = nil,
        successTransition: LoadSuccessTransition = .setContent,
        _ work: @escaping @MainActor (Self) async throws -> Void
    ) -> Task<Void, Never> {
        let typeName = String(describing: Self.self)
        let retry: Action = { [weak self] in
            guard let self else { return }
            self.performLoad(
                style: style,
                errorTitle: errorTitle,
                successTransition: successTransition,
                work
            )
        }
        return _performLoad(
            style: style,
            errorTitle: errorTitle,
            successTransition: successTransition,
            retry: retry
        ) { [weak self] in
            guard let self else {
                AppFoundationDiagnostics.reportDrop(
                    "performLoad work skipped: \(typeName) was deallocated before it ran"
                )
                throw CancellationError()
            }
            try await work(self)
        }
    }

    /// Runs an unstructured activity: owns and retains its own `Task`, independent of the
    /// caller's.
    ///
    /// The exception to `activity(_:)` above, for the same reasons as `performLoad`
    /// relative to `load(_:)`. Ideal for refresh, pagination, form submit, and background
    /// sync work whose call site can't `await` or that should survive the view. Starting a
    /// new activity cancels the in-flight one; a cancelled activity never mutates state.
    ///
    /// Same deallocation diagnostic as `performLoad`: work skipped because the view model
    /// is already gone is reported through ``AppFoundationDiagnostics`` in `DEBUG` builds.
    ///
    /// - Returns: The activity `Task`. Await it in tests for deterministic sequencing.
    @discardableResult
    public func performActivity(
        style: ActivityStyle = .overlay,
        errorHandling: BaseViewModel.ActivityErrorHandling = .banner,
        _ work: @escaping @MainActor (Self) async throws -> Void
    ) -> Task<Void, Never> {
        let typeName = String(describing: Self.self)
        return _performActivity(style: style, errorHandling: errorHandling) { [weak self] in
            guard let self else {
                AppFoundationDiagnostics.reportDrop(
                    "performActivity work skipped: \(typeName) was deallocated before it ran"
                )
                throw CancellationError()
            }
            try await work(self)
        }
    }
}
