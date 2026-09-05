import AppFoundationTestSupport
import Foundation
import Testing

// MARK: - InMemoryStore: 0% de cobertura propia (solo se ejercitaba vía Examples/NotesApp)

// `InMemoryStore` documenta dos contratos observables y fáciles de romper en un
// refactor: (1) `values()` respeta el orden de inserción, y (2) sobrescribir una clave
// existente CONSERVA su posición original — no la manda al final. Ninguno de los dos se
// deduce "por sentido común" de un diccionario Swift (que no tiene orden), así que ambos
// necesitan su propio test, no una prueba de getters.
@Suite("InMemoryStore")
struct InMemoryStoreTests {
    @Test(
        "values() devuelve los valores en el mismo orden en que se insertaron las claves, no el orden del Dictionary subyacente"
    )
    func valuesReflectInsertionOrder() async {
        let store = InMemoryStore<String, Int>()

        await store.set("c", 3)
        await store.set("a", 1)
        await store.set("b", 2)

        // Un `Dictionary` normal no garantiza este orden — si `values()` alguna vez
        // pasara a iterar `storage` directamente en vez de `insertionOrder`, este test
        // se volvería no determinista (fallaría, o pasaría por casualidad).
        #expect(await store.values() == [3, 1, 2])
    }

    @Test("set(_:_:) sobre una clave existente conserva su posición original en values(), no la mueve al final")
    func overwritingAnExistingKeyKeepsItsOriginalPosition() async {
        let store = InMemoryStore<String, String>()

        await store.set("a", "a1")
        await store.set("b", "b1")
        await store.set("c", "c1")
        await store.set("b", "b2")  // sobrescribe "b", que está en medio

        #expect(await store.values() == ["a1", "b2", "c1"])
        #expect(await store.get("b") == "b2")
    }

    @Test("remove(_:) borra el valor y su posición: el hueco no reaparece en values() ni cuenta en count/contains")
    func removeDeletesValueAndItsInsertionSlot() async {
        let store = InMemoryStore<String, Int>()
        await store.set("a", 1)
        await store.set("b", 2)
        await store.set("c", 3)

        let removed = await store.remove("b")

        #expect(removed == 2)
        #expect(await store.values() == [1, 3])
        #expect(await store.contains("b") == false)
        #expect(await store.count == 2)
        // Borrar una clave ausente no debe lanzar ni afectar nada: devuelve nil.
        let removedAgain = await store.remove("b")
        #expect(removedAgain == nil)
    }

    @Test("una clave borrada y vuelta a insertar entra como inserción NUEVA: aparece al final, no en su posición vieja")
    func reinsertingARemovedKeyAppendsAtTheEnd() async {
        let store = InMemoryStore<String, Int>()
        await store.set("a", 1)
        await store.set("b", 2)
        await store.set("c", 3)

        await store.remove("a")
        await store.set("a", 99)  // reinserción: ya no está en insertionOrder

        #expect(await store.values() == [2, 3, 99])
    }

    @Test("removeAll() vacía tanto los valores como el orden de inserción")
    func removeAllClearsValuesAndOrder() async {
        let store = InMemoryStore<String, Int>()
        await store.set("a", 1)
        await store.set("b", 2)

        await store.removeAll()

        #expect(await store.values().isEmpty)
        #expect(await store.count == 0)
        #expect(await store.contains("a") == false)

        // Y el store sigue siendo utilizable después de vaciarse.
        await store.set("z", 9)
        #expect(await store.values() == [9])
    }

    @Test("get(_:) para una clave nunca insertada devuelve nil")
    func getForAnAbsentKeyReturnsNil() async {
        let store = InMemoryStore<String, Int>()
        #expect(await store.get("nope") == nil)
    }
}
