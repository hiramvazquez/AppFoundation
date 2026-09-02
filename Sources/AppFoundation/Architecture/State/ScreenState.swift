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
}

extension BaseViewModel: ScreenState {}
