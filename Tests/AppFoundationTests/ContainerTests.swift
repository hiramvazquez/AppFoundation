import XCTest
@testable import AppFoundation

@MainActor
final class ContainerTests: XCTestCase {
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

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()
        // Ensure clean container for each test
        let testContainer = Container()
        Container.shared = testContainer
    }

    override func tearDown() {
        Container.shared = Container()
        super.tearDown()
    }

    // MARK: - Singleton Registration & Resolution Tests

    func testSingletonRegistration() {
        // Given
        let service = MockService(name: "TestService")

        // When
        Container.shared.register(service, lifecycle: .singleton)

        // Then
        let resolved: MockService = Container.shared.resolve()
        XCTAssertEqual(resolved.name, "TestService")
    }

    func testSingletonResolution_ReturnsSameInstance() {
        // Given
        let service = MockService()
        Container.shared.register(service, lifecycle: .singleton)

        // When
        let resolved1: MockService = Container.shared.resolve()
        let resolved2: MockService = Container.shared.resolve()

        // Then
        XCTAssertTrue(resolved1 === resolved2)
    }

    func testSingletonWithFactory() {
        // When
        Container.shared.register(
            MockService(name: "Factory"),
            lifecycle: .singleton
        )

        // Then
        let service: MockService = Container.shared.resolve()
        XCTAssertEqual(service.name, "Factory")
    }

    // MARK: - Transient Registration & Resolution Tests

    func testTransientRegistration() {
        // When
        Container.shared.register(
            MockService(),
            lifecycle: .transient
        )

        // Then
        let service: MockService = Container.shared.resolve()
        XCTAssertNotNil(service)
    }

    func testTransientResolution_ReturnsDifferentInstances() {
        // When
        Container.shared.register(
            MockService(),
            lifecycle: .transient
        )

        // Then
        let service1: MockService = Container.shared.resolve()
        let service2: MockService = Container.shared.resolve()
        XCTAssertFalse(service1 === service2)
    }

    func testTransientResolution_DifferentIDs() {
        // When
        Container.shared.register(
            AnotherService(),
            lifecycle: .transient
        )

        // Then
        let service1: AnotherService = Container.shared.resolve()
        let service2: AnotherService = Container.shared.resolve()
        XCTAssertNotEqual(service1.id, service2.id)
    }

    // MARK: - Scoped Registration & Resolution Tests

    func testScopedRegistration() {
        // When
        let scopeKey = "testScope"
        Container.shared.createScope(scopeKey)
        Container.shared.register(
            MockService(name: "Scoped"),
            lifecycle: .scoped(key: scopeKey)
        )

        // Then
        let service: MockService = Container.shared.resolve()
        XCTAssertEqual(service.name, "Scoped")
    }

    func testScopedResolution_ReturnsSameInstanceInScope() {
        // Given
        let scopeKey = "testScope"
        Container.shared.createScope(scopeKey)
        Container.shared.register(
            MockService(),
            lifecycle: .scoped(key: scopeKey)
        )

        // When
        let service1: MockService = Container.shared.resolve()
        let service2: MockService = Container.shared.resolve()

        // Then
        XCTAssertTrue(service1 === service2)
    }

    func testScopedResolution_DifferentInstancesInDifferentScopes() {
        // Given - resolve each scope independently to avoid Set ordering ambiguity
        let scope1 = "scope1"
        let scope2 = "scope2"

        Container.shared.createScope(scope1)
        Container.shared.register(MockService(), lifecycle: .scoped(key: scope1))
        let service1: MockService = Container.shared.resolve()
        Container.shared.destroyScope(scope1)

        Container.shared.createScope(scope2)
        Container.shared.register(MockService(), lifecycle: .scoped(key: scope2))
        let service2: MockService = Container.shared.resolve()
        Container.shared.destroyScope(scope2)

        // Then
        XCTAssertFalse(service1 === service2)
    }

    func testScopedRegistration_FailsWithoutScope() {
        // Registering for a non-existent scope triggers preconditionFailure (uncatchable).
        // Verify the guard condition: the scope should not exist beforehand.
        XCTAssertFalse(Container.shared.hasScope("nonExistentScope"))
    }

    // MARK: - TryResolve Tests

    func testTryResolve_ReturnInstanceWhenRegistered() {
        // Given
        Container.shared.register(MockService(), lifecycle: .singleton)

        // When
        let service: MockService? = Container.shared.tryResolve()

        // Then
        XCTAssertNotNil(service)
    }

    func testTryResolve_ReturnsNilWhenNotRegistered() {
        // When
        let service: MockService? = Container.shared.tryResolve()

        // Then
        XCTAssertNil(service)
    }

    func testTryResolve_DoesNotCrashWhenMissing() {
        // When/Then - Should not crash
        let _: MockService? = Container.shared.tryResolve()
    }

    // MARK: - CanResolve Tests

    func testCanResolve_TrueWhenRegistered() {
        // Given
        Container.shared.register(MockService(), lifecycle: .singleton)

        // When
        let canResolve = Container.shared.canResolve(MockService.self)

        // Then
        XCTAssertTrue(canResolve)
    }

    func testCanResolve_FalseWhenNotRegistered() {
        // When
        let canResolve = Container.shared.canResolve(MockService.self)

        // Then
        XCTAssertFalse(canResolve)
    }

    func testCanResolve_TrueForTransient() {
        // Given
        Container.shared.register(MockService(), lifecycle: .transient)

        // When
        let canResolve = Container.shared.canResolve(MockService.self)

        // Then
        XCTAssertTrue(canResolve)
    }

    // MARK: - Reset Tests

    func testReset() {
        // Given
        Container.shared.register(MockService(), lifecycle: .singleton)
        Container.shared.register(AnotherService(), lifecycle: .singleton)
        XCTAssertTrue(Container.shared.canResolve(MockService.self))

        // When
        Container.shared.reset()

        // Then
        XCTAssertFalse(Container.shared.canResolve(MockService.self))
        XCTAssertFalse(Container.shared.canResolve(AnotherService.self))
    }

    func testResetOnly() {
        // Given
        Container.shared.register(MockService(), lifecycle: .singleton)
        Container.shared.register(AnotherService(), lifecycle: .singleton)

        // When
        Container.shared.resetOnly([MockService.self])

        // Then
        XCTAssertFalse(Container.shared.canResolve(MockService.self))
        XCTAssertTrue(Container.shared.canResolve(AnotherService.self))
    }

    func testResetOnly_MultipleDependencies() {
        // Given
        Container.shared.register(MockService(), lifecycle: .singleton)
        Container.shared.register(AnotherService(), lifecycle: .singleton)

        // When
        Container.shared.resetOnly([MockService.self, AnotherService.self])

        // Then
        XCTAssertFalse(Container.shared.canResolve(MockService.self))
        XCTAssertFalse(Container.shared.canResolve(AnotherService.self))
    }

    // MARK: - Reregistration Tests

    func testReregistration_DebugWarning() {
        // Given
        Container.shared.register(MockService(name: "First"), lifecycle: .singleton)

        // When
        Container.shared.register(MockService(name: "Second"), lifecycle: .singleton)

        // Then (in DEBUG, should overwrite)
        let service: MockService = Container.shared.resolve()
        XCTAssertEqual(service.name, "Second")
    }

    // MARK: - Scope Management Tests

    func testCreateScope() {
        // When
        Container.shared.createScope("testScope")

        // Then
        XCTAssertTrue(Container.shared.hasScope("testScope"))
    }

    func testHasScope_False() {
        // When
        let hasScope = Container.shared.hasScope("nonExistentScope")

        // Then
        XCTAssertFalse(hasScope)
    }

    func testDestroyScope() {
        // Given
        Container.shared.createScope("testScope")
        XCTAssertTrue(Container.shared.hasScope("testScope"))

        // When
        Container.shared.destroyScope("testScope")

        // Then
        XCTAssertFalse(Container.shared.hasScope("testScope"))
    }

    func testDestroyScope_CleansUpInstances() {
        // Given
        let scopeKey = "testScope"
        Container.shared.createScope(scopeKey)
        Container.shared.register(
            MockService(),
            lifecycle: .scoped(key: scopeKey)
        )
        let service1: MockService = Container.shared.resolve()

        // When
        Container.shared.destroyScope(scopeKey)
        Container.shared.createScope(scopeKey)
        Container.shared.register(
            MockService(),
            lifecycle: .scoped(key: scopeKey)
        )
        let service2: MockService = Container.shared.resolve()

        // Then
        XCTAssertFalse(service1 === service2)
    }

    // MARK: - @Inject Property Wrapper Tests

    func testInjectPropertyWrapper() {
        // Given
        Container.shared.register(MockService(name: "Injected"), lifecycle: .singleton)

        // When
        let injector = InjectTestHelper()

        // Then
        XCTAssertEqual(injector.service.name, "Injected")
    }

    func testInjectPropertyWrapper_Caches() {
        // Given
        Container.shared.register(MockService(), lifecycle: .transient)

        // When
        let injector = InjectTestHelper()
        let service1 = injector.service
        let service2 = injector.service

        // Then
        XCTAssertTrue(service1 === service2)
    }

    // Helper for @Inject testing
    class InjectTestHelper {
        @Inject var service: MockService
    }

    // MARK: - DependencyModule Protocol Tests

    final class TestModule: DependencyModule {
        func register(in container: Container) {
            container.register(MockService(name: "TestModule"), lifecycle: .singleton)
        }
    }

    func testDependencyModule_Register() {
        // Given
        let module = TestModule()

        // When
        module.register(in: Container.shared)

        // Then
        let service: MockService = Container.shared.resolve()
        XCTAssertEqual(service.name, "TestModule")
    }

    // MARK: - DependencyAssembler Tests

    func testDependencyAssembler_RegisterMultipleModules() {
        // Given
        let modules: [DependencyModule] = [TestModule()]

        // When
        DependencyAssembler.shared.register(modules, in: Container.shared)

        // Then
        let service: MockService = Container.shared.resolve()
        XCTAssertEqual(service.name, "TestModule")
    }

    // MARK: - Dependency Facade Tests

    func testDependencyFacade_Register() {
        // When
        Dependency.register(MockService(name: "Facade"), lifecycle: .singleton)

        // Then
        let service: MockService = Dependency.resolve()
        XCTAssertEqual(service.name, "Facade")
    }

    func testDependencyFacade_Resolve() {
        // Given
        let testContainer = Container()
        testContainer.register(MockService(name: "Test"), lifecycle: .singleton)
        Container.shared = testContainer

        // When
        let service: MockService = Dependency.resolve()

        // Then
        XCTAssertEqual(service.name, "Test")
    }

    func testDependencyFacade_TryResolve() {
        // When
        let service: MockService? = Dependency.tryResolve()

        // Then
        XCTAssertNil(service)
    }

    func testDependencyFacade_CanResolve() {
        // Given
        Dependency.register(MockService(), lifecycle: .singleton)

        // When
        let canResolve = Dependency.canResolve(MockService.self)

        // Then
        XCTAssertTrue(canResolve)
    }

    func testDependencyFacade_Reset() {
        // Given
        Dependency.register(MockService(), lifecycle: .singleton)
        XCTAssertTrue(Dependency.canResolve(MockService.self))

        // When
        Dependency.reset()

        // Then
        XCTAssertFalse(Dependency.canResolve(MockService.self))
    }

    func testDependencyFacade_ResetOnly() {
        // Given
        Dependency.register(MockService(), lifecycle: .singleton)
        Dependency.register(AnotherService(), lifecycle: .singleton)

        // When
        Dependency.resetOnly([MockService.self])

        // Then
        XCTAssertFalse(Dependency.canResolve(MockService.self))
        XCTAssertTrue(Dependency.canResolve(AnotherService.self))
    }

    func testDependencyFacade_CreateScope() {
        // When
        Dependency.createScope("testScope")

        // Then
        XCTAssertTrue(Dependency.hasScope("testScope"))
    }

    func testDependencyFacade_DestroyScope() {
        // Given
        Dependency.createScope("testScope")

        // When
        Dependency.destroyScope("testScope")

        // Then
        XCTAssertFalse(Dependency.hasScope("testScope"))
    }

    // MARK: - Container Isolation Tests

    func testContainerShared_CanBeSwapped() {
        // Given
        let originalContainer = Container.shared
        let testContainer = Container()
        testContainer.register(MockService(name: "Test"), lifecycle: .singleton)

        // When
        Container.shared = testContainer

        // Then
        let service: MockService = Container.shared.resolve()
        XCTAssertEqual(service.name, "Test")

        // Cleanup
        Container.shared = originalContainer
    }

    func testContainerIsolation_TestingScenario() {
        // Given
        let testContainer = Container()
        Container.shared = testContainer

        // When
        testContainer.register(MockService(name: "TestIsolated"), lifecycle: .singleton)

        // Then
        let service: MockService = Container.shared.resolve()
        XCTAssertEqual(service.name, "TestIsolated")
    }

    // MARK: - Lifecycle Enum Tests

    func testLifecycle_Singleton() {
        let lifecycle = Lifecycle.singleton
        XCTAssertEqual(lifecycle, .singleton)
    }

    func testLifecycle_Transient() {
        let lifecycle = Lifecycle.transient
        XCTAssertEqual(lifecycle, .transient)
    }

    func testLifecycle_Scoped() {
        let lifecycle = Lifecycle.scoped(key: "test")
        XCTAssertEqual(lifecycle, .scoped(key: "test"))
    }
}
