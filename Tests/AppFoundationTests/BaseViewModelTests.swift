import Foundation
import Testing

@testable import AppFoundation

@Suite("BaseViewModel")
struct BaseViewModelTests {
    let viewModel = BaseViewModel()

    // MARK: - Initial State

    @Test func initialState() {
        #expect(viewModel.phase == .idle)
        #expect(viewModel.activity == ActivityState.none)
        #expect(viewModel.alert == nil)
        #expect(viewModel.banner == nil)
    }

    // MARK: - Phase Transitions

    @Test(arguments: [ActivityStyle.fullScreen, .inline, .overlay])
    func setLoadingAppliesStyle(style: ActivityStyle) {
        viewModel.setLoading(style)
        #expect(viewModel.phase == .loading(style))
        #expect(viewModel.isLoading)
    }

    @Test func setLoadingDefaultsToFullScreen() {
        viewModel.setLoading()
        #expect(viewModel.phase == .loading(.fullScreen))
    }

    @Test func setContent() {
        viewModel.setContent()
        #expect(viewModel.phase == .content)
    }

    @Test func setEmpty() {
        viewModel.setEmpty()
        #expect(viewModel.phase == .empty)
    }

    @Test func setErrorWithScreenError() {
        let error = ScreenError(title: "Test Error", message: "Something went wrong")
        viewModel.setError(error)
        #expect(viewModel.hasError)
        #expect(viewModel.currentError == error)
    }

    @Test func setErrorWithTitleAndMessage() {
        viewModel.setError(title: "Network Error", message: "Failed to connect")
        #expect(viewModel.currentError?.title == "Network Error")
        #expect(viewModel.currentError?.message == "Failed to connect")
    }

    @Test func setErrorWithRetryAction() {
        var retryWasCalled = false
        viewModel.setError(title: "Error", message: "Retry me", retry: { retryWasCalled = true })
        viewModel.currentError?.retry?()
        #expect(retryWasCalled)
    }

    @Test func setIdleResetsPhase() {
        viewModel.setContent()
        viewModel.setIdle()
        #expect(viewModel.phase == .idle)
    }

    @Test func multipleStateTransitions() {
        viewModel.setLoading()
        #expect(viewModel.phase == .loading(.fullScreen))
        viewModel.setContent()
        #expect(viewModel.phase == .content)
        viewModel.setEmpty()
        #expect(viewModel.phase == .empty)
        viewModel.setError(ScreenError(title: "E", message: "M"))
        #expect(viewModel.hasError)
        viewModel.setIdle()
        #expect(viewModel.phase == .idle)
    }

    // MARK: - Secondary Activity

    @Test func startAndStopActivity() {
        viewModel.startActivity(.overlay)
        #expect(viewModel.activity == .loading(.overlay))
        #expect(viewModel.isPerformingActivity)

        viewModel.stopActivity()
        #expect(viewModel.activity == ActivityState.none)
        #expect(!viewModel.isPerformingActivity)
    }

    // MARK: - Alerts

    @Test func showAndDismissAlert() {
        viewModel.showAlert(.info(title: "Info", message: "This is info"))
        #expect(viewModel.alert?.title == "Info")

        viewModel.dismissAlert()
        #expect(viewModel.alert == nil)
    }

    @Test func confirmationAlertRunsConfirmAction() {
        var confirmWasCalled = false
        viewModel.showAlert(
            .confirmation(
                title: "Confirm?",
                message: "Are you sure?",
                confirm: "Yes",
                cancel: "No",
                onConfirm: { confirmWasCalled = true }
            )
        )
        viewModel.alert?.primaryButton.action()
        #expect(confirmWasCalled)
    }

    @Test func destructiveAlertHasDestructiveRole() {
        viewModel.showAlert(
            .destructive(
                title: "Delete?",
                message: "Cannot undo",
                confirm: "Delete",
                cancel: "Cancel",
                onConfirm: {}
            )
        )
        #expect(viewModel.alert?.primaryButton.role == .destructive)
    }

    @Test func replaceAlertWithNewAlert() {
        viewModel.showAlert(.info(title: "Alert 1", message: "Message 1"))
        let firstID = viewModel.alert?.id
        viewModel.showAlert(.info(title: "Alert 2", message: "Message 2"))
        #expect(viewModel.alert?.id != firstID)
        #expect(viewModel.alert?.title == "Alert 2")
    }

    // MARK: - Banners

    @Test func showBannerStyles() {
        viewModel.showBanner(.success("Saved!"))
        #expect(viewModel.banner?.message == "Saved!")
        #expect(viewModel.banner?.style == .success)

        viewModel.showBanner(.error("Failed!"))
        #expect(viewModel.banner?.style == .error)

        viewModel.showBanner(.info("Info"))
        #expect(viewModel.banner?.style == .info)

        viewModel.showBanner(.warning("Warning"))
        #expect(viewModel.banner?.style == .warning)
    }

    @Test func dismissBanner() {
        viewModel.showBanner(.success("Saved!"))
        viewModel.dismissBanner()
        #expect(viewModel.banner == nil)
    }

    @Test func replaceBannerWithNewBanner() {
        viewModel.showBanner(.success("Banner 1"))
        let firstID = viewModel.banner?.id
        viewModel.showBanner(.error("Banner 2"))
        #expect(viewModel.banner?.id != firstID)
        #expect(viewModel.banner?.message == "Banner 2")
    }

    @Test func alertAndBannerCanBothDisplay() {
        viewModel.showAlert(.info(title: "Alert", message: "Alert msg"))
        viewModel.showBanner(.success("Banner msg"))
        #expect(viewModel.alert != nil)
        #expect(viewModel.banner != nil)
    }

    // MARK: - performLoad

    @Test func loadSuccessSetsContent() async throws {
        var workWasExecuted = false
        viewModel.performLoad { _ in
            workWasExecuted = true
        }
        await viewModel.inFlightLoad?.value
        #expect(workWasExecuted)
        #expect(viewModel.phase == .content)
    }

    @Test func loadFailureSetsErrorWithDefaultTitle() async throws {
        viewModel.performLoad { _ in
            throw TestError("boom")
        }
        await viewModel.inFlightLoad?.value
        #expect(viewModel.currentError?.title == "Error")
    }

    @Test func loadFailureUsesCustomErrorTitle() async throws {
        viewModel.performLoad(errorTitle: "Network Error") { _ in
            throw TestError()
        }
        await viewModel.inFlightLoad?.value
        #expect(viewModel.currentError?.title == "Network Error")
    }

    @Test func loadAppliesLoadingStyleImmediately() async throws {
        let task = viewModel.performLoad(style: .inline) { _ in }
        #expect(viewModel.phase == .loading(.inline))
        await task.value
        #expect(viewModel.phase == .content)
    }

    @Test func loadErrorProvidesRetryAction() async throws {
        viewModel.performLoad { _ in
            throw TestError()
        }
        await viewModel.inFlightLoad?.value
        #expect(viewModel.currentError?.retry != nil)
    }

    // MARK: - Computed Helpers

    @Test func computedHelpersReflectPhase() {
        #expect(viewModel.isIdle)

        viewModel.setLoading()
        #expect(
            viewModel.isLoading && !viewModel.isContent && !viewModel.isEmpty && !viewModel.hasError
                && !viewModel.isIdle
        )

        viewModel.setContent()
        #expect(viewModel.isContent && !viewModel.isLoading)
        #expect(viewModel.currentError == nil)

        viewModel.setEmpty()
        #expect(viewModel.isEmpty)

        viewModel.setError(ScreenError(title: "T", message: "M"))
        #expect(viewModel.hasError)
        #expect(viewModel.currentError == ScreenError(title: "T", message: "M"))
    }
}

// MARK: - Fase 3: tests rojos primero (A3 auto-dismiss, A1 AppErrorConvertible)

nonisolated struct DomainTestError: Error, AppErrorConvertible {
    var screenError: ScreenError {
        ScreenError(title: "Domain", message: "Friendly message")
    }
}

@Suite("BaseViewModel — Fase 3 (bugs de auditoría)")
struct BaseViewModelAuditBugTests {
    let viewModel = BaseViewModel()

    /// A3: la duration del banner debe producir un auto-dismiss REAL. `BaseViewModel`
    /// doesn't expose the banner-dismiss `Task` (only `inFlightLoad`/`inFlightActivity`),
    /// so this specifically exercises the default static `ContinuousClock()` for real —
    /// one of the explicit real-clock exceptions listed in PRD-AF-06's report (DC-AF-2).
    @Test func bannerAutoDismissesAfterItsDuration() async throws {
        // Reloj inyectado, no `Task.sleep` contra el reloj real. La versión anterior dormía
        // 200 ms esperando un banner de 50 ms y fallaba entre el 5 % y el 10 % de las veces
        // bajo `swift test --parallel` con carga: "cómodamente pasado" no es una garantía
        // cuando el scheduler tiene 57 suites compitiendo. Un test intermitente es peor que
        // no tenerlo — enseña a relanzar en vez de investigar.
        let clock = TestClock()
        let viewModel = BaseViewModel(clock: clock)

        viewModel.showBanner(BannerState(message: "Bye", style: .info, duration: .milliseconds(50)))
        #expect(viewModel.banner != nil)

        await clock.waitForSleepers()  // el auto-dismiss ya está registrado en el reloj
        clock.advance(by: .milliseconds(50))

        // Espera acotada por yields, no por tiempo real: cede el turno hasta que la tarea
        // de auto-dismiss corra su cuerpo. Si el mecanismo estuviera roto, sale del bucle
        // y FALLA — no se cuelga ni pasa por casualidad.
        for _ in 0..<1000 where viewModel.banner != nil { await Task.yield() }

        #expect(viewModel.banner == nil)
    }

    /// A3: un banner sin duration (nil = indefinido) NO se auto-descarta.
    @Test func indefiniteBannerStaysUntilDismissed() async throws {
        // Afirmar "sigue ahí tras dormir 150 ms" contra el reloj real es un verde falso
        // esperando a ocurrir: un scheduler lento aprueba el test sin haber probado nada.
        // Con reloj inyectado la aserción es más fuerte y determinista: un banner sin
        // `duration` no registra NINGÚN sleeper, así que no hay auto-dismiss que esperar.
        let clock = TestClock()
        let viewModel = BaseViewModel(clock: clock)

        viewModel.showBanner(BannerState(message: "Stay", style: .info, duration: nil))
        #expect(viewModel.banner != nil)
        #expect(clock.sleeperCount == 0, "un banner indefinido no debe programar auto-dismiss")

        viewModel.dismissBanner()
        #expect(viewModel.banner == nil)
    }

    /// A1: performLoad debe consultar AppErrorConvertible para el error de pantalla,
    /// no volcar localizedDescription crudo.
    @Test func loadFailureConsultsAppErrorConvertible() async throws {
        viewModel.performLoad { _ in
            throw DomainTestError()
        }
        await viewModel.inFlightLoad?.value
        #expect(viewModel.currentError?.title == "Domain")
        #expect(viewModel.currentError?.message == "Friendly message")
    }
}

// MARK: - Fase 3: cancelación, re-entrancy y performActivity (deterministas)

@Suite("BaseViewModel — cancelación y actividad")
struct BaseViewModelCancellationTests {
    let viewModel = BaseViewModel()

    /// C8: una carga nueva cancela la carga en vuelo, y la superada no pisa el estado.
    @Test func newLoadCancelsInFlightLoad() async {
        let first = viewModel.performLoad { _ in
            try await Task.sleep(for: .seconds(10))
        }
        let second = viewModel.performLoad { _ in }

        await second.value
        // La primera termina rápido porque su sleep fue cancelado — no en 10s.
        await first.value

        #expect(viewModel.phase == .content)
    }

    /// El doc de `inFlightLoad` promete que se limpia a `nil` al terminar "unless a newer
    /// load has already replaced it by then". `newLoadCancelsInFlightLoad` (arriba) ya
    /// prueba que la carga superada no pisa el ESTADO (`phase`); este test cierra la otra
    /// mitad del contrato: la carga superada tampoco debe dejar `inFlightLoad` en `nil`
    /// mientras la nueva sigue en curso — si lo hiciera, un consumidor que espera
    /// `inFlightLoad` (el propio README lo recomienda) vería `nil` con una carga real
    /// todavía viva. `first` usa `Task.sleep` (se cancela igual, no necesita control fino);
    /// `second` usa un `TestClock` propio para poder mantenerla en vuelo a voluntad,
    /// exactamente el punto que este test necesita observar.
    @Test func supersededLoadDoesNotClobberANewerInFlightLoad() async {
        let gate = TestClock()

        let first = viewModel.performLoad { _ in
            try await Task.sleep(for: .seconds(10))
        }
        let second = viewModel.performLoad { _ in
            try await gate.sleep(until: gate.now.advanced(by: .seconds(1)), tolerance: nil)
        }

        await first.value
        await gate.waitForSleepers()

        #expect(
            viewModel.inFlightLoad != nil,
            """
            La carga superada (generación vieja) terminó y no debía limpiar inFlightLoad \
            mientras la nueva carga sigue en curso.
            """
        )

        gate.advance(by: .seconds(1))
        await second.value

        #expect(viewModel.inFlightLoad == nil, "Al terminar la carga vigente, inFlightLoad debe quedar en nil.")
    }

    /// La cancelación no es fallo: jamás debe aparecer como error de pantalla.
    @Test func cancelledLoadDoesNotSurfaceError() async {
        let task = viewModel.performLoad { _ in
            try await Task.sleep(for: .seconds(10))
        }
        task.cancel()
        await task.value

        #expect(!viewModel.hasError)
    }

    /// preserveCurrentPhase: el trabajo decide la fase resultante.
    @Test func preserveCurrentPhaseKeepsWorkDecision() async {
        let task = viewModel.performLoad(successTransition: .preserveCurrentPhase) { vm in
            vm.setEmpty()
        }
        await task.value
        #expect(viewModel.phase == .empty)
    }

    @Test func preserveCurrentPhaseWithoutExplicitPhaseStaysLoading() async {
        let task = viewModel.performLoad(style: .overlay, successTransition: .preserveCurrentPhase) { _ in }
        await task.value
        #expect(viewModel.phase == .loading(.overlay))
    }

    // MARK: - performActivity

    @Test func activitySuccessStartsAndStops() async {
        let task = viewModel.performActivity(style: .inline) { _ in }
        #expect(viewModel.activity == .loading(.inline))
        await task.value
        #expect(viewModel.activity == ActivityState.none)
        #expect(viewModel.phase == .idle)  // activity never touches the primary phase
    }

    @Test func activityFailureSurfacesBannerByDefault() async {
        let task = viewModel.performActivity { _ in
            throw DomainTestError()
        }
        await task.value
        #expect(viewModel.activity == ActivityState.none)
        // A1 también aplica a actividades: el mensaje sale de AppErrorConvertible.
        #expect(viewModel.banner?.message == "Friendly message")
        #expect(viewModel.banner?.style == .error)
    }

    @Test func activityFailureAsAlertUsesConvertibleTitleAndMessage() async {
        let task = viewModel.performActivity(errorHandling: .alert) { _ in
            throw DomainTestError()
        }
        await task.value
        #expect(viewModel.alert?.title == "Domain")
        #expect(viewModel.alert?.message == "Friendly message")
    }

    @Test func activityFailureSilentShowsNothing() async {
        let task = viewModel.performActivity(errorHandling: .silent) { _ in
            throw TestError()
        }
        await task.value
        #expect(viewModel.banner == nil)
        #expect(viewModel.alert == nil)
        #expect(viewModel.activity == ActivityState.none)
    }

    /// Re-entrancy de actividad: la nueva cancela la anterior sin pisar su estado.
    @Test func newActivityCancelsInFlightActivity() async {
        let first = viewModel.performActivity(style: .overlay) { _ in
            try await Task.sleep(for: .seconds(10))
        }
        let second = viewModel.performActivity(style: .inline) { _ in }

        await second.value
        await first.value

        #expect(viewModel.activity == ActivityState.none)
        #expect(viewModel.banner == nil)  // la cancelación no produce banner de error
    }

    /// El retry del error reintenta la carga con los mismos parámetros.
    @Test func retryFromLoadErrorRetriesLoad() async throws {
        var attempts = 0
        let task = viewModel.performLoad { _ in
            attempts += 1
            if attempts == 1 { throw TestError("first") }
        }
        await task.value
        #expect(viewModel.hasError)

        viewModel.currentError?.retry?()
        await viewModel.inFlightLoad?.value
        #expect(attempts == 2)
        #expect(viewModel.phase == .content)
    }
}

// MARK: - Fase 3: precedencia de `clock` por instancia (DC-AF-3)

@Suite("BaseViewModel — precedencia de clock por instancia")
struct BaseViewModelClockPrecedenceTests {
    /// Proves the injected instance `clock` — not `BaseViewModel.clock`, the static
    /// default `ContinuousClock()` — is what `showBanner` schedules its auto-dismiss
    /// through, without waiting on real time: the dismiss task registers a sleeper on
    /// `testClock` if and only if the instance override actually won.
    @Test func instanceClockOverridesStaticClockForBannerDismiss() async {
        let testClock = TestClock()
        let vm = BaseViewModel(clock: testClock)

        vm.showBanner(BannerState(message: "Bye", style: .info, duration: .seconds(5)))
        await testClock.waitForSleepers()

        #expect(testClock.sleeperCount == 1)
    }
}
