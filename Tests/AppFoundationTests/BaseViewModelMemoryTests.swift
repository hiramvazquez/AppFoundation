import Foundation
import Testing

@testable import AppFoundation

// MARK: - AF-01 / AF-03: la fuga verificada por la auditoría, cerrada

/// Reproduce (adaptado a la nueva API) el test que la auditoría 2026-09-01 usó para
/// verificar la fuga: un VM en fase `.error` cuyo `work` capturaba `self` fuerte nunca se
/// liberaba (`phase → ScreenError.retry → work → self`). Con la API nueva, `work` recibe
/// el VM como parámetro — nunca lo captura — así que el ciclo no puede formarse.
@Suite("BaseViewModel — memoria (AF-01 / AF-03)")
struct BaseViewModelMemoryTests {
    /// (a) Un VM que termina en fase `.error` (con su acción de retry construida y
    /// guardada en `phase`) se libera al salir de scope.
    @Test func viewModelInErrorPhaseIsDeallocated() async throws {
        weak var weakVM: BaseViewModel?

        await {
            let vm = BaseViewModel()
            weakVM = vm
            let task = vm.performLoad { _ in
                throw TestError("boom")
            }
            await task.value
            #expect(vm.hasError)
            #expect(vm.currentError?.retry != nil)
        }()

        // `vm` was the only strong owner (`weakVM` doesn't count) — ARC releases it
        // synchronously the moment the closure above returns, no polling needed.
        #expect(weakVM == nil)
    }

    /// (b) Un VM con un load en vuelo: se suelta la última referencia externa MIENTRAS el
    /// `work` sigue suspendido (un `TestClock` controla exactamente cuándo), se cancela la
    /// carga, y el `work` observa `Task.isCancelled == true` al reanudar. Una vez el `Task`
    /// se completa, el VM se libera — nada real duerme (`TestClock`, no `Task.sleep`).
    @Test func viewModelWithInFlightLoadIsDeallocatedAndCancelsWork() async throws {
        weak var weakVM: BaseViewModel?
        let clock = TestClock()
        let recorder = Recorder()

        // Referencia fuerte explícita: se suelta a mitad de vuelo, no al salir de un
        // scope síncrono (que liberaría el VM antes de que el load llegase a arrancar).
        var vm: BaseViewModel? = BaseViewModel()
        weakVM = vm

        let task = vm!
            .performLoad { _ in
                do {
                    try await clock.sleep(until: clock.now.advanced(by: .seconds(999)), tolerance: nil)
                } catch {
                    recorder.record(Task.isCancelled ? "cancelled" : "other")
                    throw error
                }
            }

        await clock.waitForSleepers()
        vm = nil  // última referencia externa, soltada con el load en vuelo
        task.cancel()
        await task.value

        #expect(recorder.events == ["cancelled"])
        // The load's own `Task` body — the only other strong owner, via `guard let self`
        // — has already returned by the time `task.value` resumes: no polling needed.
        #expect(weakVM == nil)
    }

    /// (c) Un VM que termina en fase `.content` (sin error, sin retry pendiente) se
    /// libera con normalidad.
    @Test func viewModelInContentPhaseIsDeallocated() async throws {
        weak var weakVM: BaseViewModel?

        await {
            let vm = BaseViewModel()
            weakVM = vm
            let task = vm.performLoad { _ in }
            await task.value
            #expect(vm.isContent)
        }()

        #expect(weakVM == nil)
    }

    // MARK: - `deinit` cancela las tres tareas que retiene (inFlightLoad, inFlightActivity, bannerDismissTask)

    /// (b) de arriba (`viewModelWithInFlightLoadIsDeallocatedAndCancelsWork`) ya es la
    /// prueba de `inFlightLoad` para este contrato — con una salvedad real que vale la pena
    /// dejar escrita: `_performLoad` resuelve `[weak self]` a un `self` FUERTE antes de
    /// llamar a `_runLoad`, y esa variable local sigue viva mientras el `Task` está
    /// suspendido dentro de `work()` — así que soltar la referencia externa (`vm = nil`)
    /// NUNCA desaloja el VM por sí sola mientras la carga sigue realmente en curso;
    /// `deinit` no puede correr todavía porque el propio `Task` sigue reteniendo `self`. Se
    /// intentó aquí un test que aislara el `deinit` (sin la `task.cancel()` explícita) para
    /// no duplicar cobertura con (b): falló contra el código CORRECTO — `weakVM` seguía sin
    /// ser `nil` incluso pasados 2s — confirmando empíricamente que ese aislamiento no es
    /// observable con la forma actual de `_performLoad`. La única cancelación
    /// verdaderamente"externa" en (b) (`task.cancel()`) es, pues, necesaria — no redundante
    /// — para que el `Task` desenrolle su marco y suelte `self`; no hay forma de exigir que
    /// sea el propio `inFlightLoad?.cancel()` del `deinit` el que dispare esa cancelación
    /// sin tocar `Sources/AppFoundation`. Ver informe de la tarea para la recomendación.
    ///
    /// `inFlightActivity` comparte la misma forma (`_performActivity` resuelve `self` fuerte
    /// igual que `_performLoad`), así que este test es el análogo exacto de (b) para
    /// actividad — el hueco de cobertura real que sí se podía cerrar sin duplicar nada.
    @Test func viewModelWithInFlightActivityIsDeallocatedAndCancelsWork() async throws {
        weak var weakVM: BaseViewModel?
        let clock = TestClock()
        let recorder = Recorder()

        var vm: BaseViewModel? = BaseViewModel()
        weakVM = vm

        let task = vm!
            .performActivity { _ in
                do {
                    try await clock.sleep(until: clock.now.advanced(by: .seconds(999)), tolerance: nil)
                } catch {
                    recorder.record(Task.isCancelled ? "cancelled" : "other")
                    throw error
                }
            }

        await clock.waitForSleepers()
        vm = nil  // última referencia externa, soltada con la actividad en vuelo
        task.cancel()
        await task.value

        #expect(recorder.events == ["cancelled"])
        #expect(weakVM == nil)
    }

    /// `bannerDismissTask` no se expone públicamente (a diferencia de `inFlightLoad`/
    /// `inFlightActivity`), así que no hay `Task` que awaitear desde el test. La señal
    /// observable es indirecta pero precisa: `TestClock.sleeperCount` — si el `deinit`
    /// cancela `bannerDismissTask`, su `onCancel` retira el sleeper pendiente del reloj;
    /// si no lo hiciera, el sleeper seguiría registrado para siempre (el VM ya no existe
    /// para nadie, pero el `Task` seguiría vivo esperando un reloj que nunca avanza).
    @Test func deinitAloneCancelsBannerDismissTask() async {
        weak var weakVM: BaseViewModel?
        let clock = TestClock()

        var vm: BaseViewModel? = BaseViewModel(clock: clock)
        weakVM = vm

        vm!.showBanner(BannerState(message: "Bye", style: .info, duration: .seconds(5)))
        await clock.waitForSleepers()
        #expect(clock.sleeperCount == 1)

        vm = nil  // única fuente de cancelación en este test: el `deinit`
        #expect(weakVM == nil)

        // La cancelación del `Task` puede resolver el `onCancel` del reloj de forma no
        // estrictamente síncrona con `.cancel()`: se espera (acotado) en vez de leer
        // `sleeperCount` inmediatamente.
        await spin(until: { clock.sleeperCount == 0 })

        #expect(
            clock.sleeperCount == 0,
            """
            El deinit debía cancelar bannerDismissTask, liberando su sleeper pendiente en el reloj; \
            quedaron \(clock.sleeperCount).
            """
        )
    }

    /// El retry guardado en `ScreenError` no captura el VM: tras un error, sueltas la
    /// última referencia externa SIN invocar el retry, y el VM se libera igual — antes
    /// del fix, `retry` cerraba el ciclo permanentemente sobre `self`.
    @Test func viewModelReleasesEvenWithUnusedRetryAction() async throws {
        weak var weakVM: BaseViewModel?
        var capturedRetry: Action?

        await {
            let vm = BaseViewModel()
            weakVM = vm
            let task = vm.performLoad { _ in
                throw TestError()
            }
            await task.value
            capturedRetry = vm.currentError?.retry
        }()

        // El retry sigue siendo válido (captura el VM DÉBILMENTE) — invocarlo tras la
        // liberación del VM es un no-op seguro, nunca un crash ni una resurrección.
        #expect(weakVM == nil)
        capturedRetry?()
        #expect(weakVM == nil)
    }
}
