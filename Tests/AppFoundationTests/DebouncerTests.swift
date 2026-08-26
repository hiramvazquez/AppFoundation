import Testing
import Foundation
@testable import AppFoundation

// MARK: - Fase 3.7 (C13): Debouncer/Throttler con clock inyectable

@Suite("Debouncer")
struct DebouncerTests {
    @Test func trailingExecutesOnlyTheLastOperation() async {
        let clock = TestClock()
        let debouncer = Debouncer(delay: .milliseconds(300), edge: .trailing, clock: clock)
        let recorder = Recorder()

        await debouncer.debounce { recorder.record("1") }
        await debouncer.debounce { recorder.record("2") }
        await debouncer.debounce { recorder.record("3") }

        await clock.waitForSleepers()
        clock.advance(by: .milliseconds(300))
        await spin { recorder.count == 1 }

        #expect(recorder.events == ["3"])
    }

    @Test func trailingDoesNotExecuteBeforeTheDelay() async {
        let clock = TestClock()
        let debouncer = Debouncer(delay: .milliseconds(300), edge: .trailing, clock: clock)
        let recorder = Recorder()

        await debouncer.debounce { recorder.record("1") }
        await clock.waitForSleepers()
        clock.advance(by: .milliseconds(299))
        await Task.yield()

        #expect(recorder.count == 0)

        clock.advance(by: .milliseconds(1))
        await spin { recorder.count == 1 }
        #expect(recorder.events == ["1"])
    }

    @Test func leadingExecutesImmediatelyAndIgnoresWithinCooldown() async {
        let clock = TestClock()
        let debouncer = Debouncer(delay: .milliseconds(300), edge: .leading, clock: clock)
        let recorder = Recorder()

        await debouncer.debounce { recorder.record("A") }
        await spin { recorder.count == 1 }

        await debouncer.debounce { recorder.record("B") }  // dentro del cooldown → ignorada
        clock.advance(by: .milliseconds(300))

        await debouncer.debounce { recorder.record("C") }  // cooldown vencido → ejecuta
        await spin { recorder.count == 2 }

        #expect(recorder.events == ["A", "C"])
    }

    /// C13: cancel() cancela también la ejecución leading en vuelo.
    @Test func cancelCancelsInFlightLeadingExecution() async {
        let clock = TestClock()
        let debouncer = Debouncer(delay: .milliseconds(300), edge: .leading, clock: clock)
        let recorder = Recorder()

        await debouncer.debounce {
            do {
                try await clock.sleep(for: .milliseconds(100))
                recorder.record("L")
            } catch {
                // cancelada: no registra
            }
        }
        await clock.waitForSleepers()

        await debouncer.cancel()
        clock.advance(by: .milliseconds(300))
        await Task.yield()

        #expect(recorder.count == 0)
    }

    @Test func cancelPreventsTrailingExecution() async {
        let clock = TestClock()
        let debouncer = Debouncer(delay: .milliseconds(300), edge: .trailing, clock: clock)
        let recorder = Recorder()

        await debouncer.debounce { recorder.record("X") }
        await clock.waitForSleepers()

        await debouncer.cancel()
        clock.advance(by: .milliseconds(300))
        await Task.yield()

        #expect(recorder.count == 0)
    }

    /// C13: en .both, la ejecución trailing TAMBIÉN actualiza lastExecutionTime —
    /// una llamada inmediatamente posterior no dispara leading.
    @Test func bothEdgeTrailingExecutionUpdatesCooldown() async {
        let clock = TestClock()
        let debouncer = Debouncer(delay: .milliseconds(300), edge: .both, clock: clock)
        let recorder = Recorder()

        await debouncer.debounce { recorder.record("A") }  // leading
        await spin { recorder.count == 1 }

        await debouncer.debounce { recorder.record("B") }  // pendiente de trailing
        await clock.waitForSleepers()
        clock.advance(by: .milliseconds(300))
        await spin { recorder.count == 2 }
        #expect(recorder.events == ["A", "B"])

        // Justo después del trailing: cooldown activo → C NO ejecuta como leading.
        await debouncer.debounce { recorder.record("C") }
        await Task.yield()
        #expect(recorder.count == 2)

        // ...pero queda pendiente y ejecuta como trailing al vencer la ventana.
        await clock.waitForSleepers()
        clock.advance(by: .milliseconds(300))
        await spin { recorder.count == 3 }
        #expect(recorder.events == ["A", "B", "C"])
    }

    @Test func bothEdgeSingleCallDoesNotExecuteTwice() async {
        let clock = TestClock()
        let debouncer = Debouncer(delay: .milliseconds(300), edge: .both, clock: clock)
        let recorder = Recorder()

        await debouncer.debounce { recorder.record("A") }
        await spin { recorder.count == 1 }

        await clock.waitForSleepers()
        clock.advance(by: .milliseconds(300))
        await Task.yield()

        #expect(recorder.events == ["A"])
    }

    @Test func resetAllowsImmediateLeadingAgain() async {
        let clock = TestClock()
        let debouncer = Debouncer(delay: .milliseconds(300), edge: .leading, clock: clock)
        let recorder = Recorder()

        await debouncer.debounce { recorder.record("A") }
        await spin { recorder.count == 1 }

        await debouncer.reset()
        await debouncer.debounce { recorder.record("B") }  // sin reset sería ignorada
        await spin { recorder.count == 2 }

        #expect(recorder.events == ["A", "B"])
    }

    @Test func executeImmediatelyRunsAndCancelsPendingTrailing() async {
        let clock = TestClock()
        let debouncer = Debouncer(delay: .milliseconds(300), edge: .trailing, clock: clock)
        let recorder = Recorder()

        await debouncer.debounce { recorder.record("pending") }
        await clock.waitForSleepers()

        await debouncer.executeImmediately { recorder.record("now") }
        clock.advance(by: .milliseconds(300))
        await Task.yield()

        #expect(recorder.events == ["now"])
    }
}

@Suite("Throttler")
struct ThrottlerTests {
    @Test func executesFirstAndThrottlesWithinInterval() async {
        let clock = TestClock()
        let throttler = Throttler(interval: .seconds(1), clock: clock)
        let recorder = Recorder()

        let first = await throttler.throttle { recorder.record("1") }
        let second = await throttler.throttle { recorder.record("2") }

        #expect(first)
        #expect(!second)
        #expect(recorder.events == ["1"])
    }

    @Test func executesAgainAfterIntervalElapses() async {
        let clock = TestClock()
        let throttler = Throttler(interval: .seconds(1), clock: clock)
        let recorder = Recorder()

        await throttler.throttle { recorder.record("1") }
        clock.advance(by: .seconds(1))
        let executed = await throttler.throttle { recorder.record("2") }

        #expect(executed)
        #expect(recorder.events == ["1", "2"])
    }

    @Test func resetAllowsImmediateExecution() async {
        let clock = TestClock()
        let throttler = Throttler(interval: .seconds(1), clock: clock)
        let recorder = Recorder()

        await throttler.throttle { recorder.record("1") }
        await throttler.reset()
        let executed = await throttler.throttle { recorder.record("2") }

        #expect(executed)
        #expect(recorder.events == ["1", "2"])
    }
}
