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
