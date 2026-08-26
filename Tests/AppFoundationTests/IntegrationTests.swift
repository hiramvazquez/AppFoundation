import XCTest
@testable import AppFoundation

@MainActor
final class IntegrationTests: XCTestCase {
    // MARK: - Test Types

    enum TestRoute: Hashable {
        case home
        case detail(id: Int)
        case settings
    }

    protocol DataService: AnyObject {
        func fetchData() async throws -> String
    }

    final class MockDataService: DataService {
        var shouldFail = false
        var callCount = 0

        func fetchData() async throws -> String {
            callCount += 1
            if shouldFail {
                throw NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Fetch failed"])
            }
            return "Test Data"
        }
    }

    final class TestViewModel: BaseViewModel {
        let router: any Router<TestRoute>
        let dataService: DataService

        init(router: any Router<TestRoute>, dataService: DataService) {
            self.router = router
            self.dataService = dataService
            super.init()
        }

        func loadData() {
            load(errorTitle: "Load Failed") {
                let data = try await self.dataService.fetchData()
                print("Loaded: \(data)")
            }
        }

        func navigateToDetail(id: Int) {
            router.push(.detail(id: id))
        }
    }

    // MARK: - Setup & Teardown

    var coordinator: Coordinator<TestRoute>!
    var dataService: MockDataService!
    var viewModel: TestViewModel!

    override func setUp() {
        super.setUp()
        // Fresh container for each test
        let testContainer = Container()
        Container.shared = testContainer

        coordinator = Coordinator(root: .home)
        dataService = MockDataService()
        viewModel = TestViewModel(router: coordinator, dataService: dataService)
    }

    override func tearDown() {
        coordinator = nil
        dataService = nil
        viewModel = nil
        Container.shared = Container()
        super.tearDown()
    }

    // MARK: - DI + ViewModel Integration Tests

    func testDI_ServiceRegistration() {
        // When
        Container.shared.register(self.dataService!, lifecycle: .singleton)

        // Then
        let resolved: MockDataService = Container.shared.resolve()
        XCTAssertTrue(resolved === dataService)
    }

    func testDI_ViewModelWithInjectedService() {
        // Given
        Container.shared.register(self.dataService!, lifecycle: .singleton)

        // When
        let resolvedService: MockDataService = Container.shared.resolve()

        // Then
        XCTAssertTrue(resolvedService === dataService)
    }

    func testDI_CoordinatorRegistration() {
        // When
        Container.shared.register(self.coordinator!, lifecycle: .singleton)

        // Then
        let resolved: Coordinator<TestRoute> = Container.shared.resolve()
        XCTAssertTrue(resolved === coordinator)
    }

    // MARK: - ViewModel + Router Integration Tests

    func testViewModelRouter_Navigation() {
        // When
        viewModel.navigateToDetail(id: 123)

        // Then
        XCTAssertEqual(coordinator.mainStack.path, [.detail(id: 123)])
    }

    func testViewModelRouter_MultipleNavigation() {
        // When
        viewModel.navigateToDetail(id: 1)
        viewModel.navigateToDetail(id: 2)

        // Then
        XCTAssertEqual(coordinator.mainStack.path, [.detail(id: 1), .detail(id: 2)])
    }

    // MARK: - ViewModel + Data Service Integration Tests

    func testViewModelDataService_LoadSuccess() {
        // Given
        let expectation = XCTestExpectation(description: "Data loaded")

        // When
        viewModel.loadData()

        // Then
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.phase, .content)
            XCTAssertEqual(self.dataService.callCount, 1)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testViewModelDataService_LoadFailure() {
        // Given
        dataService.shouldFail = true
        let expectation = XCTestExpectation(description: "Load fails")

        // When
        viewModel.loadData()

        // Then
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.viewModel.hasError)
            XCTAssertEqual(self.viewModel.currentError?.title, "Load Failed")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testViewModelDataService_RetryAfterFailure() {
        // Given
        dataService.shouldFail = true
        let expectation = XCTestExpectation(description: "Retry succeeds")

        // When - First load fails
        viewModel.loadData()

        // Then - Wait for initial failure
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.viewModel.hasError)

            // When - Fix and retry
            self.dataService.shouldFail = false
            self.viewModel.currentError?.retry?()

            // Then - Retry succeeds
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                XCTAssertEqual(self.viewModel.phase, .content)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Full Flow Integration Tests

    func testFullFlow_LoadDataThenNavigate() {
        // Given
        let expectation = XCTestExpectation(description: "Full flow")

        // When - Load data
        viewModel.loadData()

        // Then - Data loads
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.phase, .content)

            // When - Navigate
            self.viewModel.navigateToDetail(id: 42)

            // Then - Navigation works
            XCTAssertEqual(self.coordinator.mainStack.path, [.detail(id: 42)])
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testFullFlow_ErrorHandlingAndRecovery() {
        // Given
        dataService.shouldFail = true
        let expectation = XCTestExpectation(description: "Error recovery")

        // When - Load fails
        viewModel.loadData()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.viewModel.hasError)

            // When - Show error alert and recover
            let alert = AlertState.info(
                title: "Error",
                message: self.viewModel.currentError?.message ?? ""
            )
            self.viewModel.showAlert(alert)
            self.dataService.shouldFail = false
            self.viewModel.currentError?.retry?()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Then - Alert shown and recovery in progress
                XCTAssertNotNil(self.viewModel.alert)
                XCTAssertEqual(self.viewModel.phase, .content)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testFullFlow_MultipleOperations() {
        // Given
        let expectation = XCTestExpectation(description: "Multiple operations")

        // When/Then - Sequence of operations
        viewModel.setLoading()
        XCTAssertTrue(viewModel.isLoading)

        viewModel.navigateToDetail(id: 1)
        XCTAssertEqual(coordinator.mainStack.path, [.detail(id: 1)])

        viewModel.loadData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.phase, .content)

            self.viewModel.showBanner(BannerState.success("Data loaded"))
            XCTAssertNotNil(self.viewModel.banner)

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Scope Lifecycle Integration Tests

    func testScope_FeatureFlowLifecycle() {
        // Given
        let scopeKey = "featureFlow"
        Container.shared.createScope(scopeKey)

        // Register scoped service
        let scopedService = MockDataService()
        Container.shared.register(scopedService, lifecycle: .scoped(key: scopeKey))

        // When - Resolve within scope
        let service1: MockDataService = Container.shared.resolve()
        let service2: MockDataService = Container.shared.resolve()

        // Then - Same instance in scope
        XCTAssertTrue(service1 === service2)

        // When - Destroy scope
        Container.shared.destroyScope(scopeKey)
        Container.shared.createScope(scopeKey)
        Container.shared.register(MockDataService(), lifecycle: .scoped(key: scopeKey))
        let service3: MockDataService = Container.shared.resolve()

        // Then - Different instance in new scope
        XCTAssertFalse(service1 === service3)
    }

    // MARK: - Constructor Injection for Testability

    func testConstructorInjection_ViewModel() {
        // Given
        let testRouter = Coordinator<TestRoute>(root: .home)
        let testService = MockDataService()

        // When
        let testVM = TestViewModel(router: testRouter, dataService: testService)

        // Then
        XCTAssertTrue(testVM.router === testRouter)
        XCTAssertTrue(testVM.dataService === testService)
    }

    func testConstructorInjection_Testability() {
        // Given
        let testRouter = Coordinator<TestRoute>(root: .home)
        let testService = MockDataService()
        testService.shouldFail = false

        // When
        let vm = TestViewModel(router: testRouter, dataService: testService)
        vm.loadData()

        // Then
        let expectation = XCTestExpectation(description: "Loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(vm.phase, .content)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Module Assembly Integration Tests

    final class TestFeatureModule: DependencyModule {
        let dataService: DataService

        init(dataService: DataService) {
            self.dataService = dataService
        }

        func register(in container: Container) {
            container.register(self.dataService, lifecycle: .singleton)
        }
    }

    func testModuleAssembly_RegisterFeature() {
        // Given
        let module = TestFeatureModule(dataService: dataService)

        // When
        module.register(in: Container.shared)

        // Then
        let resolved: DataService = Container.shared.resolve()
        XCTAssertTrue(resolved === dataService)
    }

    func testModuleAssembly_WithAssembler() {
        // Given
        let modules: [DependencyModule] = [
            TestFeatureModule(dataService: dataService)
        ]

        // When
        DependencyAssembler.shared.register(modules, in: Container.shared)

        // Then
        let resolved: DataService = Container.shared.resolve()
        XCTAssertTrue(resolved === dataService)
    }

    // MARK: - State + Navigation Integration Tests

    func testStateNavigation_AlertThenNavigate() {
        // When
        viewModel.setLoading()
        viewModel.showAlert(AlertState.info(title: "Wait", message: "Loading"))

        // Then
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNotNil(viewModel.alert)

        // When - Dismiss and navigate
        viewModel.dismissAlert()
        viewModel.setContent()
        viewModel.navigateToDetail(id: 1)

        // Then
        XCTAssertNil(viewModel.alert)
        XCTAssertTrue(viewModel.isContent)
        XCTAssertEqual(coordinator.mainStack.path, [.detail(id: 1)])
    }

    func testStateNavigation_ModalPresentation() {
        // When
        viewModel.navigateToDetail(id: 1)
        coordinator.present(.settings, as: .sheet)

        // Then
        XCTAssertEqual(coordinator.mainStack.path, [.detail(id: 1)])
        XCTAssertTrue(coordinator.isSheetPresented)
        XCTAssertFalse(coordinator.isAtRoot)

        // When - Dismiss modal
        coordinator.dismiss()

        // Then
        XCTAssertFalse(coordinator.isSheetPresented)
        XCTAssertEqual(coordinator.activeLayer, .main)
    }

    func testStateNavigation_ErrorWithRetry() {
        // Given
        dataService.shouldFail = true
        let expectation = XCTestExpectation(description: "Error retry flow")

        // When - Load and show error
        viewModel.loadData()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Navigate with error state
            self.viewModel.navigateToDetail(id: 100)
            XCTAssertTrue(self.viewModel.hasError)
            XCTAssertEqual(self.coordinator.mainStack.path, [.detail(id: 100)])

            // Show error alert
            if let error = self.viewModel.currentError {
                let alert = AlertState.info(
                    title: error.title,
                    message: error.message
                )
                self.viewModel.showAlert(alert)
                XCTAssertNotNil(self.viewModel.alert)

                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }
}
