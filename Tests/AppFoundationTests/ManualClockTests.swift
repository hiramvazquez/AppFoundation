import AppFoundationTestSupport
import Foundation
import Testing

// MARK: - ManualClock: 0% de cobertura propia — el más crítico de los tres

// `ManualClock` es el doble de tiempo que usan todos los tests deterministas del propio
// paquete (`BaseViewModel`, `Debouncer`/`Throttler`) y de los ejemplos (vía
// `NetworkingConfiguration(clock:)`). Un bug aquí no se detecta ejercitando ManualClock
// directamente en ningún sitio hoy — lo detectaría (o no) un test de más alto nivel dando
// un falso verde, exactamente el escenario que este fichero cierra.
//
// Contratos verificados, tomados del doc comment y del cuerpo de cada método (no
// inventados):
// - `sleep(until:)` no vuelve hasta que `advance(by:)` cruza la deadline.
// - `advance(by:)` solo despierta a quien tenga deadline `<= now`; el resto queda pendiente.
// - `advance(by:)` que cruza varias deadlines a la vez las despierta a TODAS — ninguna
//   se pierde por quedarse solo con la primera o cortar el filtrado a medias.
// - `pendingDeadlines` lista en ORDEN DE REGISTRO (no ordenado), según su propio doc.
// - cancelar el `Task` que duerme lo saca de la lista de espera y lanza `CancellationError`.
// - `waitUntilSleeping()` no vuelve hasta que hay, como mínimo, un sleeper registrado.
//
// NO se comprueba con espías cruzando `Task`s independientes el orden de EJECUCIÓN
// posterior a `resume()` para varios sleepers que vencen a la vez (`advance` sí los
// ordena por deadline internamente — `ready.sorted { $0.deadline < $1.deadline }` — antes
// de invocar `resume()` en ese orden): confirmado empíricamente que, aun forzando
// `@MainActor in` en las tres tareas, el orden en que su código POSTERIOR a `sleep`
// llega a ejecutarse no es determinista (~15% de las ejecuciones lo reordenan) — Swift
// Concurrency no garantiza que resumir continuations en un orden concreto implique que el
// código que sigue a cada una se ejecute en ese mismo orden. Afirmar ese orden con un test
// habría sido exactamente el tipo de test intermitente que este encargo pide evitar.
@Suite("ManualClock")
struct ManualClockTests {
    @Test("Instant.duration(to:) mide el intervalo hacia adelante (self → other), no al revés")
    func instantDurationToMeasuresTheForwardInterval() {
        let clock = ManualClock()
        let start = clock.now
        let later = start.advanced(by: .seconds(5))

        // Si la resta se invirtiera (`offset - other.offset` en vez de
        // `other.offset - offset`), ambos resultados saldrían con el signo cambiado.
        #expect(start.duration(to: later) == .seconds(5))
        #expect(later.duration(to: start) == .seconds(-5))
    }

    @Test("sleep(until:) no resume hasta que advance(by:) alcanza o supera la deadline")
    func sleepSuspendsUntilDeadlineIsReached() async throws {
        let clock = ManualClock()
        var didWake = false

        let task = Task {
            try await clock.sleep(until: clock.now.advanced(by: .seconds(2)))
            didWake = true
        }

        await clock.waitUntilSleeping()
        clock.advance(by: .seconds(1))  // todavía por debajo de los 2s de deadline

        // Sin `advance` real de tiempo: solo cedemos el hilo para dejar correr el
        // scheduler. Si `sleep` despertara antes de tiempo, `didWake` ya sería true aquí.
        for _ in 0..<50 { await Task.yield() }
        #expect(didWake == false)
        #expect(clock.pendingDeadlines.count == 1)

        clock.advance(by: .seconds(1))  // ahora sí: 1s + 1s == deadline
        try await task.value

        #expect(didWake)
    }

    @Test("sleep(until:) con una deadline igual o anterior a now devuelve el control sin registrarse como sleeper")
    func sleepWithNonFutureDeadlineReturnsImmediately() async throws {
        let clock = ManualClock()
        let start = clock.now

        // deadline == now: el `guard deadline > s.now` de la implementación NO debe
        // registrar este sleep como pendiente.
        try await clock.sleep(until: start)
        #expect(clock.pendingDeadlines.isEmpty)

        clock.advance(by: .seconds(5))

        // deadline (start) ahora queda en el pasado respecto al clock ya avanzado.
        try await clock.sleep(until: start)
        #expect(clock.pendingDeadlines.isEmpty)
    }

    @Test("advance(by:) solo despierta a los sleepers cuya deadline ya se alcanzó; los demás siguen pendientes")
    func advanceOnlyWakesSleepersWhoseDeadlineIsDue() async throws {
        let clock = ManualClock()

        let soon = Task { try await clock.sleep(until: clock.now.advanced(by: .seconds(1))) }
        let later = Task { try await clock.sleep(until: clock.now.advanced(by: .seconds(5))) }

        while clock.pendingDeadlines.count < 2 { await Task.yield() }

        clock.advance(by: .seconds(1))
        try await soon.value  // si no despertara, este await colgaría el test

        // `later` no debe haberse movido: sigue como el único pendiente.
        #expect(clock.pendingDeadlines.count == 1)

        clock.advance(by: .seconds(4))
        try await later.value
        #expect(clock.pendingDeadlines.isEmpty)
    }

    @Test("advance(by:) que cruza varias deadlines a la vez despierta a TODOS los sleepers due, ninguno se pierde")
    func advanceResumesEveryDueSleeperAtOnce() async throws {
        let clock = ManualClock()

        // Registrados a propósito fuera de orden de deadline: 3s, luego 1s, luego 2s —
        // si `advance(by:)` alguna vez procesara solo el primero que encuentra, o
        // cortara el filtrado tras el primer no-due, esto lo detectaría.
        let taskC = Task { try await clock.sleep(until: clock.now.advanced(by: .seconds(3))) }
        while clock.pendingDeadlines.count < 1 { await Task.yield() }
        let taskA = Task { try await clock.sleep(until: clock.now.advanced(by: .seconds(1))) }
        while clock.pendingDeadlines.count < 2 { await Task.yield() }
        let taskB = Task { try await clock.sleep(until: clock.now.advanced(by: .seconds(2))) }
        while clock.pendingDeadlines.count < 3 { await Task.yield() }

        clock.advance(by: .seconds(3))  // vencen los tres a la vez

        // Si `advance` hubiera perdido a alguno, el `await` correspondiente colgaría el
        // test (o el runner lo mataría por timeout) en vez de devolver un booleano falso
        // — el modo de fallo correcto para "nunca se resume".
        try await taskA.value
        try await taskB.value
        try await taskC.value

        #expect(clock.pendingDeadlines.isEmpty)
    }

    @Test("pendingDeadlines lista en ORDEN DE REGISTRO, no ordenado por deadline (documentado explícitamente)")
    func pendingDeadlinesReflectsRegistrationOrderNotDeadlineOrder() async throws {
        let clock = ManualClock()
        let zero = clock.now

        let taskLate = Task { try await clock.sleep(until: zero.advanced(by: .seconds(5))) }
        while clock.pendingDeadlines.count < 1 { await Task.yield() }
        let taskEarly = Task { try await clock.sleep(until: zero.advanced(by: .seconds(1))) }
        while clock.pendingDeadlines.count < 2 { await Task.yield() }
        let taskMid = Task { try await clock.sleep(until: zero.advanced(by: .seconds(3))) }
        while clock.pendingDeadlines.count < 3 { await Task.yield() }

        // Registrado en orden 5s, 1s, 3s: si `pendingDeadlines` alguna vez ordenara por
        // deadline, este test lo detectaría (esperaríamos [1s, 3s, 5s]).
        #expect(
            clock.pendingDeadlines == [
                zero.advanced(by: .seconds(5)),
                zero.advanced(by: .seconds(1)),
                zero.advanced(by: .seconds(3))
            ]
        )

        clock.advance(by: .seconds(5))
        try await taskLate.value
        try await taskEarly.value
        try await taskMid.value
    }

    @Test("cancelar el Task que duerme lo saca de pendingDeadlines y su sleep(until:) lanza CancellationError")
    func cancellingASleepingTaskRemovesItFromTheClock() async throws {
        let clock = ManualClock()
        var caughtCancellation = false

        let task = Task {
            do {
                try await clock.sleep(until: clock.now.advanced(by: .seconds(10)))
            } catch is CancellationError {
                caughtCancellation = true
            }
        }

        await clock.waitUntilSleeping()
        #expect(clock.pendingDeadlines.count == 1)

        task.cancel()
        try await task.value

        #expect(caughtCancellation)
        // El sleeper cancelado no debe seguir ocupando sitio en el reloj: un
        // `advance(by:)` posterior no debe intentar resolver una continuation ya muerta.
        #expect(clock.pendingDeadlines.isEmpty)
    }

    @Test("waitUntilSleeping() no vuelve hasta que hay, al menos, un sleeper registrado")
    func waitUntilSleepingDoesNotReturnBeforeASleeperRegisters() async throws {
        let clock = ManualClock()
        var waiterCompleted = false

        let waiter = Task {
            await clock.waitUntilSleeping()
            waiterCompleted = true
        }

        // Dejamos correr el scheduler todo lo posible SIN registrar ningún sleeper: si
        // `waitUntilSleeping()` volviera de inmediato (bug), `waiterCompleted` ya sería
        // true aquí, antes de que exista ningún sleeper.
        for _ in 0..<50 { await Task.yield() }
        #expect(waiterCompleted == false)

        let sleeper = Task { try await clock.sleep(until: clock.now.advanced(by: .seconds(1))) }
        await waiter.value
        #expect(waiterCompleted)

        clock.advance(by: .seconds(1))
        try await sleeper.value
    }
}
