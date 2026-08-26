import Testing
import Foundation
@testable import AppFoundation

// MARK: - Fase 5: el doc dice thread-safe — demostrado con TaskGroup

/// Registrado y resuelto desde fuera del MainActor: el contrato del Container exige
/// tipos Sendable para eso, y estos tests lo respetan.
nonisolated final class SendableProbe: Sendable {
    let value: Int
    init(value: Int) { self.value = value }
}

/// Registra una factory formada en contexto nonisolated (segura fuera del MainActor).
nonisolated func registerLazyProbe(in container: Container, value: Int) {
    container.register(SendableProbe(value: value), lifecycle: .singleton)
}

nonisolated func registerTransientProbe(in container: Container) {
    container.register(SendableProbe(value: Int.random(in: 0..<1_000_000)), lifecycle: .transient)
}

@Suite("Container — concurrencia (TaskGroup)")
struct ContainerConcurrencyTests {
    @Test func concurrentResolutionOfSingletonReturnsOneInstance() async {
        let container = Container()
        registerLazyProbe(in: container, value: 42)

        let identifiers = await withTaskGroup(of: ObjectIdentifier.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    let probe: SendableProbe = container.resolve()
                    return ObjectIdentifier(probe)
                }
            }
            var collected: Set<ObjectIdentifier> = []
            for await id in group { collected.insert(id) }
            return collected
        }

        // C4: double-checked correcto — la carrera de creación lazy converge en UNA
        // instancia almacenada, por muchos resolvers concurrentes que haya.
        #expect(identifiers.count == 1)
    }

    @Test func concurrentTransientResolutionIsSafeAndDistinct() async {
        let container = Container()
        registerTransientProbe(in: container)

        let identifiers = await withTaskGroup(of: ObjectIdentifier.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    let probe: SendableProbe = container.resolve()
                    return ObjectIdentifier(probe)
                }
            }
            var collected: [ObjectIdentifier] = []
            for await id in group { collected.append(id) }
            return collected
        }

        #expect(identifiers.count == 50)
    }

    @Test func concurrentRegistrationAndResolutionDoesNotCorruptState() async {
        let container = Container()
        registerLazyProbe(in: container, value: 1)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    if i.isMultiple(of: 2) {
                        _ = container.tryResolve(SendableProbe.self)
                    } else {
                        _ = container.canResolve(SendableProbe.self)
                    }
                }
            }
            for i in 0..<10 {
                group.addTask {
                    container.createScope("scope-\(i)")
                    container.destroyScope("scope-\(i)")
                }
            }
        }

        #expect(container.canResolve(SendableProbe.self))
        let probe: SendableProbe = container.resolve()
        #expect(probe.value == 1)
    }

    @Test func concurrentChildResolutionAgainstSharedParent() async {
        let parent = Container()
        registerLazyProbe(in: parent, value: 7)

        let values = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    let child = Container(parent: parent)
                    let probe: SendableProbe = child.resolve()
                    return probe.value
                }
            }
            var collected: [Int] = []
            for await value in group { collected.append(value) }
            return collected
        }

        #expect(values.allSatisfy { $0 == 7 })
    }
}
