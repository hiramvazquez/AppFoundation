import Testing
import Foundation
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

    /// Every test uses its own container — `Container.shared` is immutable and is never
    /// touched by the suite.
    let container = Container()

    // MARK: - Singleton

    @Test func singletonRegistrationResolvesInstance() {
        container.register(MockService(name: "TestService"), lifecycle: .singleton)
        let resolved: MockService = container.resolve()
        #expect(resolved.name == "TestService")
    }

    @Test func singletonResolutionReturnsSameInstance() {
        container.register(MockService(), lifecycle: .singleton)
        let resolved1: MockService = container.resolve()
        let resolved2: MockService = container.resolve()
        #expect(resolved1 === resolved2)
    }

    @Test func singletonFactoryRunsLazilyOnFirstResolve() {
        var factoryRuns = 0
        container.register({ () -> MockService in
            factoryRuns += 1
            return MockService(name: "Lazy")
        }(), lifecycle: .singleton)

        // Autoclosure wraps the whole expression: not executed at registration time.
        #expect(factoryRuns == 0)

        let resolved: MockService = container.resolve()
        #expect(factoryRuns == 1)
        #expect(resolved.name == "Lazy")

        _ = container.resolve(MockService.self)
        #expect(factoryRuns == 1)
    }

    // MARK: - Transient

    @Test func transientResolutionReturnsDifferentInstances() {
        container.register(MockService(), lifecycle: .transient)
        let service1: MockService = container.resolve()
        let service2: MockService = container.resolve()
        #expect(service1 !== service2)
    }

    @Test func transientInstancesHaveDifferentIdentity() {
        container.register(AnotherService(), lifecycle: .transient)
        let service1: AnotherService = container.resolve()
        let service2: AnotherService = container.resolve()
        #expect(service1.id != service2.id)
    }

    // MARK: - Scoped

    @Test func scopedRegistrationResolvesInstance() {
        container.createScope("testScope")
        container.register(MockService(name: "Scoped"), lifecycle: .scoped(key: "testScope"))
        let service: MockService = container.resolve()
        #expect(service.name == "Scoped")
    }

    @Test func scopedResolutionReturnsSameInstanceInScope() {
        container.createScope("testScope")
        container.register(MockService(), lifecycle: .scoped(key: "testScope"))
        let service1: MockService = container.resolve()
        let service2: MockService = container.resolve()
        #expect(service1 === service2)
    }

    @Test func destroyedScopeDropsItsInstances() {
        container.createScope("testScope")
        container.register(MockService(), lifecycle: .scoped(key: "testScope"))
        let service1: MockService = container.resolve()

        container.destroyScope("testScope")
        container.createScope("testScope")
        container.register(MockService(), lifecycle: .scoped(key: "testScope"))
        let service2: MockService = container.resolve()

        #expect(service1 !== service2)
    }

    /// C6: when two scopes register the same type, resolution is deterministic —
    /// the most recently created scope wins.
    @Test func mostRecentlyCreatedScopeWinsResolution() {
        container.createScope("older")
        container.register(MockService(name: "older"), lifecycle: .scoped(key: "older"))
        container.createScope("newer")
        container.register(MockService(name: "newer"), lifecycle: .scoped(key: "newer"))

        let resolved: MockService = container.resolve()
        #expect(resolved.name == "newer")

        container.destroyScope("newer")
        let afterDestroy: MockService = container.resolve()
        #expect(afterDestroy.name == "older")
    }

    // MARK: - Scope Management

    @Test func createAndDestroyScope() {
        container.createScope("testScope")
        #expect(container.hasScope("testScope"))

        container.destroyScope("testScope")
        #expect(!container.hasScope("testScope"))
    }

    @Test func hasScopeIsFalseForUnknownScope() {
        #expect(!container.hasScope("nonExistentScope"))
    }

    // MARK: - tryResolve / canResolve

    @Test func tryResolveReturnsInstanceWhenRegistered() {
        container.register(MockService(), lifecycle: .singleton)
        let service: MockService? = container.tryResolve()
        #expect(service != nil)
    }

    @Test func tryResolveReturnsNilWhenNotRegistered() {
        let service: MockService? = container.tryResolve()
        #expect(service == nil)
    }

    @Test func canResolveReflectsRegistrations() {
        #expect(!container.canResolve(MockService.self))
        container.register(MockService(), lifecycle: .singleton)
        #expect(container.canResolve(MockService.self))

        container.register(AnotherService(), lifecycle: .transient)
        #expect(container.canResolve(AnotherService.self))
    }

    // MARK: - Reset

    @Test func resetClearsAllRegistrations() {
        container.register(MockService(), lifecycle: .singleton)
        container.register(AnotherService(), lifecycle: .singleton)

        container.reset()

        #expect(!container.canResolve(MockService.self))
        #expect(!container.canResolve(AnotherService.self))
    }

    @Test func resetOnlyClearsSelectedTypes() {
        container.register(MockService(), lifecycle: .singleton)
        container.register(AnotherService(), lifecycle: .singleton)

        container.resetOnly([MockService.self])

        #expect(!container.canResolve(MockService.self))
        #expect(container.canResolve(AnotherService.self))
    }

    // MARK: - Re-registration

    @Test func reRegistrationOverwrites() {
        container.register(MockService(name: "First"), lifecycle: .singleton)
        container.register(MockService(name: "Second"), lifecycle: .singleton)
        let service: MockService = container.resolve()
        #expect(service.name == "Second")
    }

    @Test func reRegistrationAfterResolutionOverwrites() {
        container.register(MockService(name: "First"), lifecycle: .singleton)
        _ = container.resolve(MockService.self)
        container.register(MockService(name: "Second"), lifecycle: .singleton)
        let service: MockService = container.resolve()
        #expect(service.name == "Second")
    }

    // MARK: - Child Containers (the override mechanism)

    @Test func childFallsBackToParent() {
        container.register(MockService(name: "Parent"), lifecycle: .singleton)
        let child = Container(parent: container)

        let resolved: MockService = child.resolve()
        #expect(resolved.name == "Parent")
        #expect(child.canResolve(MockService.self))
    }

    @Test func childRegistrationShadowsParentWithoutMutatingIt() {
        container.register(MockService(name: "Parent"), lifecycle: .singleton)
        let child = Container(parent: container)
        child.register(MockService(name: "Child"), lifecycle: .singleton)

        let fromChild: MockService = child.resolve()
        let fromParent: MockService = container.resolve()
        #expect(fromChild.name == "Child")
        #expect(fromParent.name == "Parent")
    }

    @Test func sharedContainerIsImmutable() {
        // The API offers no setter; this documents the contract.
        #expect(Container.shared === Container.shared)
    }

    // MARK: - @Inject

    @MainActor
    final class InjectTestHelper {
        @Inject var service: MockService
        init(container: Container) {
            _service = Inject(container: container)
        }
    }

    @Test func injectResolvesFromProvidedContainer() {
        container.register(MockService(name: "Injected"), lifecycle: .singleton)
        let helper = InjectTestHelper(container: container)
        #expect(helper.service.name == "Injected")
    }

    @Test func injectCachesFirstResolution() {
        container.register(MockService(), lifecycle: .transient)
        let helper = InjectTestHelper(container: container)
        let service1 = helper.service
        let service2 = helper.service
        #expect(service1 === service2)
    }

    // MARK: - DependencyModule

    final class TestModule: DependencyModule {
        func register(in container: Container) {
            container.register(MockService(name: "TestModule"), lifecycle: .singleton)
        }
    }

    @Test func moduleRegistersIntoContainer() {
        TestModule().register(in: container)
        let service: MockService = container.resolve()
        #expect(service.name == "TestModule")
    }

    @Test func registerModulesAppliesAllInOrder() {
        container.register(modules: [TestModule()])
        let service: MockService = container.resolve()
        #expect(service.name == "TestModule")
    }
}
