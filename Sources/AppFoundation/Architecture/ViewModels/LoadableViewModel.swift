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
/// keeps `self` alive. That is what makes the view model deallocate — while a load is in
/// flight, while it's showing a retryable error, in every case — and what makes `deinit`
/// actually cancel the in-flight work instead of never running.
public protocol LoadableViewModel: BaseViewModel {}

extension BaseViewModel: LoadableViewModel {}

extension LoadableViewModel {
    /// Runs a primary load operation, switching `phase` to `.loading` immediately.
    ///
    /// Best for initial screen loads. Use `successTransition: .preserveCurrentPhase` when
    /// `work` decides the resulting phase itself (e.g. `.empty` vs `.content`).
    ///
    /// Starting a new load cancels the in-flight one (re-entrancy); the superseded task
    /// never mutates screen state after cancellation. A cancelled load never becomes a
    /// screen error — neither does any error `BaseViewModel.cancellationRecognizer`
    /// recognizes as cancellation.
    ///
    /// On failure, `work` is retried, unchanged, through the `ScreenError.retry` action —
    /// which is why `work` must not capture `self`: the retry closure only captures the
    /// view model weakly, so a rejected screen releases cleanly.
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
            guard let self else { throw CancellationError() }
            try await work(self)
        }
    }

    /// Runs secondary work while keeping the current screen content visible.
    ///
    /// Ideal for refresh, pagination, form submit, and background sync work. Starting a
    /// new activity cancels the in-flight one; a cancelled activity never mutates state.
    ///
    /// - Returns: The activity `Task`. Await it in tests for deterministic sequencing.
    @discardableResult
    public func performActivity(
        style: ActivityStyle = .overlay,
        errorHandling: BaseViewModel.ActivityErrorHandling = .banner,
        _ work: @escaping @MainActor (Self) async throws -> Void
    ) -> Task<Void, Never> {
        _performActivity(style: style, errorHandling: errorHandling) { [weak self] in
            guard let self else { throw CancellationError() }
            try await work(self)
        }
    }

    /// Structured variant of `performLoad`: runs `work` inline in the caller's `Task`
    /// instead of an unstructured one owned by the view model.
    ///
    /// Use it from `.task { await vm.load { … } }`: SwiftUI cancels the view's `.task`
    /// when the view disappears, so cancellation follows the view instead of `deinit`.
    /// The `Task`-returning `performLoad` remains the right choice for button actions,
    /// where the operation should outlive the tap.
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
        await _runLoad(style: style, errorTitle: errorTitle, successTransition: successTransition, retry: retry) {
            try await work(self)
        }
    }

    /// Structured variant of `performActivity`: runs `work` inline in the caller's
    /// `Task`. See `load(...)` for when to prefer this over `performActivity`.
    public func activity(
        style: ActivityStyle = .overlay,
        errorHandling: BaseViewModel.ActivityErrorHandling = .banner,
        _ work: @escaping @MainActor (Self) async throws -> Void
    ) async {
        await _runActivity(style: style, errorHandling: errorHandling) {
            try await work(self)
        }
    }
}
