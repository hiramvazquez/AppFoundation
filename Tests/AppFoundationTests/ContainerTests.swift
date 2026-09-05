import Foundation
import Testing

@testable import AppFoundation

@Suite("Container")
struct ContainerTests {
    // MARK: - Test Types

    protocol TestService: AnyObject {
        var name: String { get }
    }

    final class MockService: TestService {
        let name: String
        init(name: String = "Mock") {
            self.name = name
        }
    }

    final class AnotherService {
        let id: String = UUID().uuidString
    }

    /// Depends on `MockService`: its factory resolves it from the container it receives.
    final class Consumer {
        let service: MockService
        init(service: MockService) { self.service = service }
    }

    /// Every test uses its own container — `Container.shared` is immutable and is never
    /// touched by the suite.
    let container = Container()

    // MARK: - Singleton

    @Test func singletonRegistrationResolvesInstance() {
        container.register(MockService.self) { _ in MockService(name: "TestService") }
        let resolved: MockService = container.resolve()
        #expect(resolved.name == "TestService")
    }

    @Test func singletonIsTheDefaultLifecycle() {
        container.register { _ in MockService() }
        let resolved1: MockService = container.resolve()
        let resolved2: MockService = container.resolve()
        #expect(resolved1 === resolved2)
    }

    @Test func singletonFactoryRunsLazilyOnFirstResolve() {
        var factoryRuns = 0
        container.register(MockService.self) { _ in
            factoryRuns += 1
            return MockService(name: "Lazy")
        }

        #expect(factoryRuns == 0)

        let resolved: MockService = container.resolve()
        #expect(factoryRuns == 1)
        #expect(resolved.name == "Lazy")

        _ = container.resolve(MockService.self)
        #expect(factoryRuns == 1)
    }

    @Test func registerInstanceHandsOutThatObject() {
        let instance = MockService(name: "Prebuilt")
        container.register(instance: instance)

        let resolved: MockService = container.resolve()
        #expect(resolved === instance)
    }

    @Test func registerInstanceAsProtocolResolvesTheAbstraction() {
        let instance = MockService(name: "Abstract")
        container.register(instance: instance, as: TestService.self)

        let resolved: TestService = container.resolve()
        #expect(resolved === instance)
        #expect(!container.canResolve(MockService.self))
    }

    // MARK: - Transient

    @Test func transientResolutionReturnsDifferentInstances() {
        container.register(MockService.self, lifecycle: .transient) { _ in MockService() }
        let service1: MockService = container.resolve()
        let service2: MockService = container.resolve()
        #expect(service1 !== service2)
    }

    @Test func transientInstancesHaveDifferentIdentity() {
        container.register(AnotherService.self, lifecycle: .transient) { _ in AnotherService() }
        let service1: AnotherService = container.resolve()
        let service2: AnotherService = container.resolve()
        #expect(service1.id != service2.id)
    }

    // MARK: - Factories resolve their own dependencies

    /// AF-09: the factory receives the container, so it resolves its dependencies from
    /// the same place it was registered in — no global, no lock to avoid re-entering.
    @Test func factoryResolvesItsDependenciesFromTheSameContainer() {
        container.register(MockService.self) { _ in MockService(name: "Dependency") }
        container.register(Consumer.self) { c in Consumer(service: c.resolve()) }

        let consumer: Consumer = container.resolve()
        let service: MockService = container.resolve()
        #expect(consumer.service === service)
        #expect(consumer.service.name == "Dependency")
    }

    @Test func factoryRegisteredInParentResolvesFromTheParent() {
        container.register(MockService.self) { _ in MockService(name: "Parent") }
        container.register(Consumer.self) { c in Consumer(service: c.resolve()) }

        let child = Container(parent: container)
        child.register(MockService.self) { _ in MockService(name: "Child") }

        // The parent's singleton must never be built with a child's override: that is what
        // keeps `Container.shared` free of test doubles.
        let consumer: Consumer = child.resolve()
        #expect(consumer.service.name == "Parent")
    }

    @Test func nestedResolutionLeavesTheResolutionStackEmpty() {
        container.register(MockService.self) { _ in MockService() }
        container.register(Consumer.self) { c in Consumer(service: c.resolve()) }

        _ = container.resolve(Consumer.self)
        #expect(!container.isResolving)
    }

    // MARK: - Cycle detection (the guard, not the trap)

    @Test func resolutionStackDetectsDirectCycleNamingBothTypes() {
        var stack = ResolutionStack()
        #expect(stack.push(ObjectIdentifier(MockService.self), name: "A") == nil)
        #expect(stack.push(ObjectIdentifier(AnotherService.self), name: "B") == nil)

        let message = stack.push(ObjectIdentifier(MockService.self), name: "A")
        #expect(message?.contains("A → B → A") == true)
        #expect(message?.contains("cycle") == true)
    }

    @Test func resolutionStackReportsOnlyTheCyclicSegment() {
        var stack = ResolutionStack()
        _ = stack.push(ObjectIdentifier(Consumer.self), name: "Root")
        _ = stack.push(ObjectIdentifier(MockService.self), name: "A")
        _ = stack.push(ObjectIdentifier(AnotherService.self), name: "B")

        let message = stack.push(ObjectIdentifier(MockService.self), name: "A")
        #expect(message?.contains("A → B → A") == true)
        #expect(message?.contains("Root") == false)
    }

    @Test func resolutionStackPopRestoresLegitimateResolution() {
        var stack = ResolutionStack()
        _ = stack.push(ObjectIdentifier(MockService.self), name: "A")
        stack.pop()
        #expect(stack.isEmpty)
        #expect(stack.push(ObjectIdentifier(MockService.self), name: "A") == nil)
    }

    // Test negativo (no compila, por diseño — AF-09): resolver desde `nonisolated`.
    //
    //     nonisolated func resolveOffMainActor(_ container: Container) -> MockService {
    //         container.resolve()
    //     }
    //
    //     error: call to main actor-isolated instance method 'resolve' in a synchronous
    //            nonisolated context
    //
    // El código `nonisolated` recibe la dependencia ya resuelta por su `init`.

    // MARK: - Child container per flow (replaces `.scoped`)

    /// AF-10: what used to be the string-keyed scope lifecycle (create the scope, register
    /// against its key, destroy the scope) is a child container owned by the flow. Same
    /// lifetime semantics, no string keys, nothing to forget to destroy.
    @Test func childContainerPerFlowSharesInstancesWithinTheFlow() {
        let flow = Container(parent: container)
        flow.register(MockService.self) { _ in MockService(name: "Flow") }

        let service1: MockService = flow.resolve()
        let service2: MockService = flow.resolve()
        #expect(service1 === service2)
        #expect(service1.name == "Flow")
    }

    @Test func aNewFlowGetsNewInstances() {
        let firstFlow = Container(parent: container)
        firstFlow.register(MockService.self) { _ in MockService() }
        let first: MockService = firstFlow.resolve()

        let secondFlow = Container(parent: container)
        secondFlow.register(MockService.self) { _ in MockService() }
        let second: MockService = secondFlow.resolve()

        #expect(first !== second)
    }

    @Test func flowRegistrationsNeverLeakIntoTheParent() {
        let flow = Container(parent: container)
        flow.register(MockService.self) { _ in MockService() }
        _ = flow.resolve(MockService.self)

        #expect(!container.canResolve(MockService.self))
        #expect(container.tryResolve(MockService.self) == nil)
    }

    // MARK: - tryResolve / canResolve

    @Test func tryResolveReturnsInstanceWhenRegistered() {
        container.register(MockService.self) { _ in MockService() }
        let service: MockService? = container.tryResolve()
        #expect(service != nil)
    }

    @Test func tryResolveReturnsNilWhenNotRegistered() {
        let service: MockService? = container.tryResolve()
        #expect(service == nil)
    }

    @Test func canResolveReflectsRegistrations() {
        #expect(!container.canResolve(MockService.self))
        container.register(MockService.self) { _ in MockService() }
        #expect(container.canResolve(MockService.self))

        container.register(AnotherService.self, lifecycle: .transient) { _ in AnotherService() }
        #expect(container.canResolve(AnotherService.self))
    }

    // MARK: - Reset

    @Test func resetClearsAllRegistrations() {
        container.register(MockService.self) { _ in MockService() }
        container.register(instance: AnotherService())

        container.reset()

        #expect(!container.canResolve(MockService.self))
        #expect(!container.canResolve(AnotherService.self))
        #expect(container.tryResolve(AnotherService.self) == nil)
    }

    @Test func resetLeavesTheParentUntouched() {
        container.register(MockService.self) { _ in MockService() }
        let child = Container(parent: container)
        child.register(AnotherService.self) { _ in AnotherService() }

        child.reset()

        #expect(!child.canResolve(AnotherService.self))
        #expect(child.canResolve(MockService.self))
    }

    // MARK: - Re-registration

    @Test func reRegistrationOverwrites() {
        container.register(MockService.self) { _ in MockService(name: "First") }
        container.register(MockService.self) { _ in MockService(name: "Second") }
        let service: MockService = container.resolve()
        #expect(service.name == "Second")
    }

    @Test func reRegistrationAfterResolutionDropsTheCachedSingleton() {
        container.register(MockService.self) { _ in MockService(name: "First") }
        _ = container.resolve(MockService.self)
        container.register(MockService.self) { _ in MockService(name: "Second") }
        let service: MockService = container.resolve()
        #expect(service.name == "Second")
    }

    @Test func reRegistrationReplacesAPrebuiltInstance() {
        container.register(instance: MockService(name: "Prebuilt"))
        container.register(MockService.self) { _ in MockService(name: "Factory") }
        let service: MockService = container.resolve()
        #expect(service.name == "Factory")
    }

    // MARK: - Child Containers (the override mechanism)

    @Test func childFallsBackToParent() {
        container.register(MockService.self) { _ in MockService(name: "Parent") }
        let child = Container(parent: container)

        let resolved: MockService = child.resolve()
        #expect(resolved.name == "Parent")
        #expect(child.canResolve(MockService.self))
    }

    @Test func childRegistrationShadowsParentWithoutMutatingIt() {
        container.register(MockService.self) { _ in MockService(name: "Parent") }
        let child = Container(parent: container)
        child.register(MockService.self) { _ in MockService(name: "Child") }

        let fromChild: MockService = child.resolve()
        let fromParent: MockService = container.resolve()
        #expect(fromChild.name == "Child")
        #expect(fromParent.name == "Parent")
    }

    @Test func sharedContainerIsImmutable() {
        // The API offers no setter; this documents the contract.
        #expect(Container.shared === Container.shared)
    }

    // MARK: - DEBUG diagnostics

    @Test func registeredTypesListsLocalRegistrationsSorted() {
        container.register(MockService.self) { _ in MockService() }
        container.register(instance: AnotherService())
        let child = Container(parent: container)

        let names = container.registeredTypes()
        #expect(names.count == 2)
        #expect(names == names.sorted())
        #expect(names.contains { $0.hasSuffix("MockService") })
        #expect(names.contains { $0.hasSuffix("AnotherService") })
        #expect(child.registeredTypes().isEmpty)
    }

    @Test func validateRegistrationsPassesWhenEverythingIsPresent() {
        container.register(MockService.self) { _ in MockService() }
        let child = Container(parent: container)
        child.register(instance: AnotherService())

        // Would `assertionFailure` if anything were missing.
        child.validateRegistrations([MockService.self, AnotherService.self])
    }

    // MARK: - @Inject

    final class InjectTestHelper {
        @Inject var service: MockService
        init(container: Container) {
            _service = Inject(container: container)
        }
    }

    @Test func injectResolvesFromProvidedContainer() {
        container.register(MockService.self) { _ in MockService(name: "Injected") }
        let helper = InjectTestHelper(container: container)
        #expect(helper.service.name == "Injected")
    }

    @Test func injectCachesFirstResolution() {
        container.register(MockService.self, lifecycle: .transient) { _ in MockService() }
        let helper = InjectTestHelper(container: container)
        let service1 = helper.service
        let service2 = helper.service
        #expect(service1 === service2)
    }

    // MARK: - DependencyModule

    struct TestModule: DependencyModule {
        func register(in container: Container) {
            container.register(MockService.self) { _ in MockService(name: "TestModule") }
        }
    }

    @Test func moduleRegistersIntoContainer() {
        TestModule().register(in: container)
        let service: MockService = container.resolve()
        #expect(service.name == "TestModule")
    }

    @Test func registerModulesAppliesAllInOrder() {
        struct OverridingModule: DependencyModule {
            func register(in container: Container) {
                container.register(MockService.self) { _ in MockService(name: "Later") }
            }
        }

        container.register(modules: [TestModule(), OverridingModule()])
        let service: MockService = container.resolve()
        #expect(service.name == "Later")
    }

    // MARK: - register(modules:) — orden de array (doc: "assembles them in order" / "applied in array order")

    /// Grabador simple de eventos: `DependencyModule.register(in:)` no es `async`, así que
    /// un `SpyRecorder` (actor) no serviría — no se puede `await` desde una función
    /// síncrona. `Container`/`DependencyModule` son `@MainActor` y este archivo hereda el
    /// mismo aislamiento por defecto, así que un array plano basta.
    private final class ModuleOrderRecorder {
        private(set) var events: [String] = []
        func record(_ event: String) { events.append(event) }
        deinit {}
    }

    /// Módulo espía: registra su paso por `register(in:)` antes de ejecutar el registro
    /// real que le pasa el test.
    private struct OrderRecordingModule: DependencyModule {
        let name: String
        let recorder: ModuleOrderRecorder
        let work: (Container) -> Void

        func register(in container: Container) {
            recorder.record(name)
            work(container)
        }
    }

    /// El doc de `register(modules:)` lo promete dos veces ("assembles them in order",
    /// "applied in array order"). Hasta ahora ningún test lo comprobaba con un espía — todo
    /// uso real registra un único módulo. Si alguien invirtiera el `for module in modules`
    /// a `.reversed()`, ambos módulos seguirían registrándose (nada rompería a nivel de
    /// tipo), pero en el orden equivocado — y esto es lo único que lo detecta.
    @Test func registerModulesCallsRegisterInInOrder() {
        let recorder = ModuleOrderRecorder()
        let first = OrderRecordingModule(name: "First", recorder: recorder) { _ in }
        let second = OrderRecordingModule(name: "Second", recorder: recorder) { _ in }

        container.register(modules: [first, second])

        #expect(
            recorder.events == ["First", "Second"],
            "Se esperaba invocar register(in:) en orden de array [First, Second]; se observó \(recorder.events)."
        )
    }

    /// Prueba el orden con algo observable además de la llamada en sí: el último módulo
    /// que registra el MISMO tipo gana (ya cubierto arriba por `registerModulesAppliesAllInOrder`,
    /// sin espía) — aquí se combina con el espía para dejar constancia de ambas señales a la vez.
    @Test func registerModulesLastModuleForSameTypeWinsAndRunsLast() {
        let recorder = ModuleOrderRecorder()
        let first = OrderRecordingModule(name: "First", recorder: recorder) { c in
            c.register(MockService.self) { _ in MockService(name: "From-First") }
        }
        let second = OrderRecordingModule(name: "Second", recorder: recorder) { c in
            c.register(MockService.self) { _ in MockService(name: "From-Second") }
        }

        container.register(modules: [first, second])
        let service: MockService = container.resolve()

        #expect(
            recorder.events == ["First", "Second"],
            "Orden de registro observado: \(recorder.events)"
        )
        #expect(
            service.name == "From-Second",
            "El último módulo del array debía ganar para el mismo tipo; resolvió \(service.name)."
        )
    }

    /// Si el segundo módulo depende de algo que registra el primero (resolviéndolo en el
    /// momento del registro, no de forma perezosa), debe poder resolverlo — lo que solo se
    /// cumple si `register(modules:)` de verdad aplica los módulos en orden de array.
    @Test func aLaterModuleCanResolveWhatAnEarlierModuleRegistered() {
        struct BaseModule: DependencyModule {
            func register(in container: Container) {
                container.register(MockService.self) { _ in MockService(name: "Base") }
            }
        }
        struct DependentModule: DependencyModule {
            let recorder: ModuleOrderRecorder
            func register(in container: Container) {
                // Resuelve YA, durante el registro — no espera a una resolución perezosa
                // posterior — para que el orden de array importe de verdad.
                let dependency: MockService? = container.tryResolve()
                recorder.record(dependency == nil ? "missing" : "present:\(dependency!.name)")
                container.register(instance: Consumer(service: dependency ?? MockService(name: "MISSING")))
            }
        }

        let recorder = ModuleOrderRecorder()
        container.register(modules: [BaseModule(), DependentModule(recorder: recorder)])
        let consumer: Consumer = container.resolve()

        #expect(
            consumer.service.name == "Base",
            """
            El segundo módulo debía poder resolver la dependencia registrada por el primero; \
            recorder.events=\(recorder.events)
            """
        )
    }
}
