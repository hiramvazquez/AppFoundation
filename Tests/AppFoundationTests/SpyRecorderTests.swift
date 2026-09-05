import AppFoundationTestSupport
import Foundation
import Testing

// MARK: - SpyRecorder: 0% de cobertura propia (solo se ejercitaba vía Examples/*)

// El doc del tipo promete tres cosas concretas: (1) `calls` conserva el ORDEN de
// grabación, (2) `isEmpty`/`wasCalled` son negación exacta el uno del otro sobre
// `calls.isEmpty`, y (3) es seguro grabar desde varias tareas concurrentes a la vez —
// literalmente la razón de ser de un `actor` en vez de una clase con lock manual.
@Suite("SpyRecorder")
struct SpyRecorderTests {
    @Test("record(_:) conserva el orden de grabación en calls")
    func recordPreservesOrder() async {
        let spy = SpyRecorder<String>()

        await spy.record("first")
        await spy.record("second")
        await spy.record("third")

        #expect(await spy.calls == ["first", "second", "third"])
        #expect(await spy.count == 3)
    }

    @Test("isEmpty y wasCalled reflejan el estado antes y después de la primera grabación, como negación exacta")
    func isEmptyAndWasCalledAreExactOpposites() async {
        let spy = SpyRecorder<Int>()

        #expect(await spy.isEmpty)
        #expect(await spy.wasCalled == false)

        await spy.record(1)

        #expect(await spy.isEmpty == false)
        #expect(await spy.wasCalled)
    }

    @Test("reset() vacía el historial y deja el spy como recién creado")
    func resetClearsHistory() async {
        let spy = SpyRecorder<Int>()
        await spy.record(1)
        await spy.record(2)

        await spy.reset()

        #expect(await spy.calls.isEmpty)
        #expect(await spy.count == 0)
        #expect(await spy.isEmpty)

        // Y sigue siendo utilizable después de reset().
        await spy.record(9)
        #expect(await spy.calls == [9])
    }

    @Test("la variante Call == Void cuenta las llamadas sin argumentos, una entrada por invocación")
    func voidVariantCountsCallsWithoutArguments() async {
        let spy = SpyRecorder<Void>()

        await spy.record()
        await spy.record()
        await spy.record()

        #expect(await spy.count == 3)
        #expect(await spy.wasCalled)
    }

    // MARK: - Concurrencia (la razón de ser de `actor`)

    @Test("grabar concurrentemente desde muchas tareas no pierde ni duplica llamadas")
    func recordingConcurrentlyFromManyTasksIsSafe() async {
        let spy = SpyRecorder<Int>()
        let taskCount = 200

        await withTaskGroup(of: Void.self) { group in
            for value in 0..<taskCount {
                group.addTask { await spy.record(value) }
            }
        }

        let calls = await spy.calls
        // El orden entre tareas concurrentes no está garantizado, pero NINGUNA
        // grabación puede perderse ni duplicarse: eso es justo lo que un actor (frente a
        // una clase sin protección) garantiza.
        #expect(calls.count == taskCount)
        #expect(Set(calls) == Set(0..<taskCount))
    }
}
