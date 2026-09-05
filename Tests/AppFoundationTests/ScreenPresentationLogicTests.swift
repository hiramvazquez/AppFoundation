#if canImport(SwiftUI)
import Testing
@testable import AppFoundation

// MARK: - Fase 5: colapso de actividad — cada estilo renderiza algo (A2 como test)

@Suite("ScreenPresentationLogic")
struct ScreenPresentationLogicTests {
    /// A2 muerto por construcción: TODO estilo de loading produce un overlay visible —
    /// el .inline invisible de la versión anterior es irrepresentable.
    @Test(arguments: [ActivityStyle.fullScreen, .inline, .overlay])
    func everyLoadingStyleRendersAVisibleOverlay(style: ActivityStyle) {
        #expect(ScreenPresentationLogic.phaseOverlay(for: .loading(style)) == .loading(style))
    }

    @Test(arguments: [ActivityStyle.fullScreen, .inline, .overlay])
    func everySecondaryActivityStyleRendersAnIndicator(style: ActivityStyle) {
        #expect(ScreenPresentationLogic.activityIndicator(for: .loading(style)) == style)
    }

    @Test func noActivityRendersNoIndicator() {
        #expect(ScreenPresentationLogic.activityIndicator(for: .none) == nil)
    }

    /// Solo el fullScreen primario oculta el contenido; inline y overlay lo dejan visible.
    @Test func onlyFullScreenLoadingHidesContent() {
        #expect(ScreenPresentationLogic.hidesContent(.loading(.fullScreen)))
        #expect(!ScreenPresentationLogic.hidesContent(.loading(.inline)))
        #expect(!ScreenPresentationLogic.hidesContent(.loading(.overlay)))
    }

    @Test func errorAndEmptyReplaceContent() {
        #expect(ScreenPresentationLogic.hidesContent(.error(ScreenError(title: "E", message: "M"))))
        #expect(ScreenPresentationLogic.hidesContent(.empty))

        let error = ScreenError(title: "E", message: "M")
        #expect(ScreenPresentationLogic.phaseOverlay(for: .error(error)) == .error(error))
        #expect(ScreenPresentationLogic.phaseOverlay(for: .empty) == .empty)
    }

    @Test func idleAndContentShowContentWithNoOverlay() {
        for phase in [ViewPhase.idle, .content] {
            #expect(!ScreenPresentationLogic.hidesContent(phase))
            #expect(ScreenPresentationLogic.phaseOverlay(for: phase) == .none)
        }
    }

    // MARK: - `shouldCancelInFlightWork`: the pure decision behind ScreenContainer's
    // cancel-on-removal watchdog (see its doc comment on `ScreenContainer`).

    /// Opted in, and the watchdog's wait was actually interrupted by cancellation (the view
    /// was genuinely removed) — the only case that should fire.
    @Test func firesOnlyWhenEnabledAndTheWatchdogWasCancelled() {
        #expect(
            ScreenPresentationLogic.shouldCancelInFlightWork(cancelsOnRemoval: true, watchdogWasCancelled: true)
        )
    }

    /// Opted out (`cancelsInFlightWorkOnRemoval: false`) never fires, even if the watchdog
    /// were somehow cancelled anyway — the escape hatch for work that must survive the view.
    @Test func neverFiresWhenOptedOut() {
        #expect(
            !ScreenPresentationLogic.shouldCancelInFlightWork(cancelsOnRemoval: false, watchdogWasCancelled: true)
        )
        #expect(
            !ScreenPresentationLogic.shouldCancelInFlightWork(cancelsOnRemoval: false, watchdogWasCancelled: false)
        )
    }

    /// Opted in, but the wait ended WITHOUT cancellation — the (never actually reached in
    /// practice) case of the sleep's duration elapsing on its own. Must not fire: nothing
    /// was removed.
    @Test func doesNotFireWhenEnabledButNotCancelled() {
        #expect(
            !ScreenPresentationLogic.shouldCancelInFlightWork(cancelsOnRemoval: true, watchdogWasCancelled: false)
        )
    }
}
#endif
