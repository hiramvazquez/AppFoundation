import Testing

@testable import AppFoundation

// MARK: - PRD-AF-07: `Logic` marker protocol

/// `CounterLogicProtocol`/`CounterLogic` below are the smallest possible shape a
/// "sin datos" (no `Service`/`Store`) feature's `Logic` takes: no dependencies at all,
/// pure business logic (`ARQUITECTURA-KIT-2026-09-02.md` §1, variant table).
private protocol CounterLogicProtocol: Logic {
    func increment(_ value: Int) -> Int
}

private final class CounterLogic: CounterLogicProtocol {
    func increment(_ value: Int) -> Int { value + 1 }
}

@Suite("Logic (PRD-AF-07)")
struct LogicTests {
    @Test("A concrete Logic conforms to the marker protocol and is usable through it")
    func concreteLogicConformsToMarker() {
        let logic: any CounterLogicProtocol = CounterLogic()

        #expect(logic.increment(0) == 1)
        // Compiles because `CounterLogicProtocol: Logic` — proves the marker composes
        // with a feature-specific protocol without adding requirements of its own.
        let asLogic: any Logic = logic
        _ = asLogic
    }

    @Test("Logic is a class-bound (AnyObject) protocol")
    func logicIsClassBound() {
        // `CounterLogic` is a `final class`; conforming to `Logic: AnyObject` compiles
        // only for reference types. Identity is preserved through the protocol.
        let logic = CounterLogic()
        let asProtocol: any CounterLogicProtocol = logic
        #expect(ObjectIdentifier(asProtocol) == ObjectIdentifier(logic))
    }
}
