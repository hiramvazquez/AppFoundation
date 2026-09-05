import Observation

/// What a screen shell (`ScreenContainer`, `.screen(_:)`) needs to observe and close out
/// (AF-05, `AUDITORIA-2026-09-01.md` — decisión del propietario). Before this protocol
/// existed, `ScreenContainer` took a concrete `BaseViewModel`, so any screen that wanted
/// the shell had to inherit from it even when it only used four of its properties.
/// `ScreenState` is the minimal contract instead: `BaseViewModel` conforms below, but any
/// other `@Observable` class can conform too — `ScreenContainer` depends on this protocol,
/// never on `BaseViewModel` itself.
///
/// `phase`/`activity` are read-only from the shell's perspective: `ScreenContainer` renders
/// them, it never sets them — only the state's own methods (`setLoading`, `setContent`,
/// `startActivity`, ...) do. `alert`/`banner` are `{ get set }` because the shell dismisses
/// them itself (tapping the alert's button, a banner's auto-dismiss timer).
@MainActor
public protocol ScreenState: AnyObject, Observable {
    /// The main screen state right now (idle / loading / content / empty / error).
    var phase: ViewPhase { get }

    /// Secondary work that should not replace the current content.
    var activity: ActivityState { get }

    /// Current alert to display, if any. Settable so the shell can dismiss it.
    var alert: AlertState? { get set }

    /// Current banner/toast notification to display, if any. Settable so the shell can
    /// dismiss it (tap, or auto-dismiss).
    var banner: BannerState? { get set }

    /// Cancels whatever unstructured work this screen state owns in flight.
    ///
    /// `ScreenContainer` calls this when its view is actually removed from the view
    /// hierarchy — not merely covered by a pushed screen — for a state that opts in
    /// (`ScreenContainer`'s `cancelsInFlightWorkOnRemoval`, the default). It exists because
    /// `performLoad`/`performActivity` start an unstructured `Task` that a view model
    /// retains: while that `Task`'s `work` is actually running, it holds the view model
    /// strongly, so releasing the view's last reference to it does not free it, and
    /// `deinit` cannot cancel a `Task` it no longer has the chance to run before
    /// deallocation. Cancelling from the view's lifecycle — before the last reference is
    /// even released — reaches the `Task` while it is still cancellable. See
    /// `BaseViewModel`'s "What `deinit` actually cancels" for the full contract.
    ///
    /// Defaults to a no-op via the extension below, so this requirement is purely
    /// additive: any existing `ScreenState` conformance outside this package keeps
    /// compiling unchanged. `BaseViewModel` overrides it to cancel `inFlightLoad` and
    /// `inFlightActivity`.
    func cancelInFlightWork()
}

extension ScreenState {
    /// No-op default — see the requirement's doc comment. A conformance that has no
    /// unstructured work to cancel (or that manages its own lifecycle independently of
    /// `ScreenContainer`) never needs to implement this.
    public func cancelInFlightWork() {}
}

extension BaseViewModel: ScreenState {}
