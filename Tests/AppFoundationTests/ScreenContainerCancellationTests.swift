#if canImport(SwiftUI)
import SwiftUI
import Testing

@testable import AppFoundation

// MARK: - ScreenContainer's cancel-on-removal watchdog
//
// `ScreenContainer` cancels a screen's in-flight work (`ScreenState.cancelInFlightWork()`)
// when its view is genuinely removed from the hierarchy — never when merely covered by a
// pushed screen. The two halves of that claim need very different verification:
//
// 1. "Cancelling the watchdog `Task` calls `cancelInFlightWork()` (unless opted out)" is
//    OUR code, and is a real unit test below (`ScreenContainer.runRemovalWatchdog()` is
//    `internal`, not `private`, exactly so this file can drive it directly).
//
// 2. "SwiftUI cancels a view's `.task` only on genuine removal, never on being covered by a
//    push" is SwiftUI's own behavior, not this package's — and this package's test target
//    has no way to exercise it: there is no live window/host here (`swift test` runs
//    headless, no simulator, no `NavigationStack` driven by real navigation), and
//    `ImageRenderer` — this package's usual stand-in for "does it render," used throughout
//    `RenderSmokeTests` — does NOT drive the full attach/detach lifecycle a `.task` needs:
//    an empirical probe (`ImageRenderer(content:).cgImage`, then dropping the renderer)
//    left a `performLoad`'s `Task` running uncancelled for the full 2-second timeout used
//    to detect cancellation elsewhere in this file — ImageRenderer produces a single frame,
//    it doesn't tear down a mounted view graph the way a real view removal does.
//
//    Point 2 was instead verified empirically OUTSIDE this package, with a throwaway SwiftUI
//    macOS app (`WindowGroup` + `NavigationStack`) logging to a file across a two-level
//    push/pop:
//
//        PUSH B (root -> B)
//        B .task STARTED
//        PUSH C (B -> C): B is now COVERED, not removed
//        still on C after 1s of being covered (checking B did not cancel while covered)
//        POP TO ROOT (removes both B and C from the stack)
//        B .task CANCELLED
//
//    B's `.task` survived being covered by C for a full second, and only cancelled once
//    `path.removeAll()` actually removed B from the stack — confirming `.task` tracks view
//    IDENTITY IN THE HIERARCHY, not on-screen visibility, exactly the distinction
//    `onDisappear` (which fires on every push, covered or not) gets wrong for this feature.
//    This also matches Apple's documented behavior for `task(priority:_:)`. Manual QA before
//    shipping a screen that leans on this: push forward from it while a `performLoad` is in
//    flight and confirm (breakpoint/log on `cancelInFlightWork()`) it does NOT fire, then pop
//    back and confirm it does.
//
//    ACTUALIZACIÓN (sept. 2026): el punto 2 de arriba ya NO depende solo de esta QA manual.
//    `Scripts/verify-lifecycle-contract.sh` + `Sources/LifecycleContractProbeApp/` (un
//    ejecutable, no un test — `swift test` no lo toca) reproducen exactamente esta secuencia
//    en una app real con ventana, y salen con exit != 0 si el orden observado no es el
//    esperado. Ver el encabezado de ese script para cómo se invoca y por qué, honestamente,
//    solo está confirmado en local por ahora (el job de CI que lo invoca arranca con
//    `continue-on-error: true` hasta confirmar un run limpio en GitHub Actions).
//
//    Al reverificar para construir ese script (Xcode/macOS con toolchain Swift 6.3.3) salió
//    un hallazgo que vale la pena dejar por escrito: `onDisappear` NO disparó al tapar B con
//    C, ni con este harness (`NSApplication` a mano) ni con una `App`/`WindowGroup` real —
//    solo disparó junto con la eliminación genuina en el pop. Es decir, la frase de arriba
//    ("onDisappear fires on every push, covered or not") no se pudo reproducir en este SDK:
//    en la versión de SwiftUI probada aquí, `onDisappear` parece seguir la misma semántica de
//    IDENTIDAD que `.task`, no la de visibilidad en pantalla. Eso no invalida la elección de
//    `.task` como mecanismo — sigue siendo correcto — pero sí sugiere que el riesgo concreto
//    que motivó descartar `onDisappear` puede haber cambiado (o no aplicar igual en macOS
//    que en iOS, o nunca haberse revalidado desde que se escribió este comentario). Es
//    precisamente el tipo de deriva de comportamiento de SwiftUI entre versiones que
//    `verify-lifecycle-contract.sh` existe para detectar automáticamente en vez de a ojo.
/// Minimal `ScreenViewModel` that only exists to record whether/how many times
/// `cancelInFlightWork()` was called — the container-level tests below don't need a real
/// `BaseViewModel` (that contract is `BaseViewModelMemoryTests`' job); they need to prove
/// `ScreenContainer` actually calls the requirement when its watchdog is cancelled. Declared
/// at file scope, not nested in the test suite, because `@Observable`'s macro-generated
/// `Observable` conformance needs at least `fileprivate` visibility for the type it extends.
@Observable
@MainActor
private final class RecordingScreenState: ScreenState, ActionHandling {
    private(set) var phase: ViewPhase = .content
    private(set) var activity: ActivityState = .none
    var alert: AlertState?
    var banner: BannerState?

    private(set) var cancelInFlightWorkCallCount = 0

    func cancelInFlightWork() {
        cancelInFlightWorkCallCount += 1
    }

    enum Action: Sendable {}
    func handle(_ action: Action) {}
}

@Suite("ScreenContainer — cancel-on-removal watchdog")
struct ScreenContainerCancellationTests {
    /// Default (`cancelsInFlightWorkOnRemoval: true`): cancelling the watchdog `Task` — the
    /// stand-in for the view being genuinely removed — calls `cancelInFlightWork()` exactly
    /// once.
    @MainActor
    @Test func cancellingTheWatchdogCallsCancelInFlightWorkByDefault() async {
        let state = RecordingScreenState()
        let container = ScreenContainer(state) { _ in EmptyView() }

        let watchdog = Task { await container.runRemovalWatchdog() }
        watchdog.cancel()
        await watchdog.value

        #expect(state.cancelInFlightWorkCallCount == 1)
    }

    /// Opted out (`cancelsInFlightWorkOnRemoval: false`): the watchdog returns immediately
    /// without ever calling `cancelInFlightWork()`, cancelled or not — the escape hatch for
    /// work that must survive the view on purpose (an upload, a submit).
    @MainActor
    @Test func optingOutNeverCallsCancelInFlightWorkEvenWhenCancelled() async {
        let state = RecordingScreenState()
        let container = ScreenContainer(state, cancelsInFlightWorkOnRemoval: false) { _ in EmptyView() }

        let watchdog = Task { await container.runRemovalWatchdog() }
        watchdog.cancel()
        await watchdog.value

        #expect(state.cancelInFlightWorkCallCount == 0)
    }

    /// `ScreenContainer(observing:)` builds an `ObservingScreenState` wrapper around
    /// `state` — this proves its `cancelInFlightWork()` pass-through (see its doc comment)
    /// actually reaches the wrapped view model, not just that it type-checks.
    @MainActor
    @Test func observingInitializerForwardsCancelInFlightWorkToTheWrappedState() async {
        let state = RecordingScreenState()
        let container = ScreenContainer(observing: state) { EmptyView() }

        let watchdog = Task { await container.runRemovalWatchdog() }
        watchdog.cancel()
        await watchdog.value

        #expect(state.cancelInFlightWorkCallCount == 1)
    }

    /// End-to-end with the real `BaseViewModel` contract instead of the recording double:
    /// a `ScreenContainer` wrapping a view model with a genuinely in-flight `performLoad`
    /// has its watchdog cancelled, and the load actually gets cancelled and the view model
    /// deallocates — the same shape as `BaseViewModelMemoryTests`'
    /// `cancelInFlightWorkCancelsAnInFlightLoadAndAllowsDeallocation`, but reached through
    /// `ScreenContainer` instead of calling `cancelInFlightWork()` directly.
    @MainActor
    @Test func endToEndThroughScreenContainerCancelsAnInFlightLoadAndAllowsDeallocation() async throws {
        weak var weakVM: BaseViewModel?
        let clock = TestClock()
        let recorder = Recorder()

        // `ScreenContainer`'s `state` (here, `ObservingScreenState` wrapping `vm`) is a
        // stored property of a struct that would otherwise stay alive for this whole test
        // function — keeping `vm` retained regardless of `vm = nil` below. Scoping
        // `container`/`vm`/the tasks inside this closure, exactly like the other
        // deallocation tests in `BaseViewModelMemoryTests`, is what lets ARC actually
        // release everything before `weakVM` is checked.
        await {
            var vm: BaseViewModel? = BaseViewModel()
            weakVM = vm

            let loadTask = vm!
                .performLoad { _ in
                    do {
                        try await clock.sleep(until: clock.now.advanced(by: .seconds(999)), tolerance: nil)
                    } catch {
                        recorder.record(Task.isCancelled ? "cancelled" : "other")
                        throw error
                    }
                }
            await clock.waitForSleepers()

            let container = ScreenContainer(observing: vm!) { EmptyView() }
            let watchdog = Task { await container.runRemovalWatchdog() }
            watchdog.cancel()
            await watchdog.value

            await loadTask.value
            vm = nil
        }()

        #expect(recorder.events == ["cancelled"])
        #expect(weakVM == nil)
    }
}
#endif
