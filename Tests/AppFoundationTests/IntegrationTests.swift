import Testing
import Foundation
@testable import AppFoundation

@Suite("Integration: DI + ViewModel + Router")
struct IntegrationTests {
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
                throw TestError("Fetch failed")
            }
            return "Test Data"
        }
    }

    final class TestViewModel: BaseViewModel, ActionHandling {
        let router: any Router<TestRoute>
        let dataService: DataService

        /// AF-05: the single entry point a view — or a test standing in for one — uses.
        enum Action: Sendable {
            case loadData
            case navigateToDetail(id: Int)
        }

        init(router: any Router<TestRoute>, dataService: DataService) {
            self.router = router
            self.dataService = dataService
            super.init()
        }

        func handle(_ action: Action) {
            switch action {
            case .loadData: loadData()
            case .navigateToDetail(let id): navigateToDetail(id: id)
            }
        }

        @discardableResult
        func loadData() -> Task<Void, Never> {
            performLoad(errorTitle: "Load Failed") { vm in
                _ = try await vm.dataService.fetchData()
            }
        }

        func navigateToDetail(id: Int) {
            router.push(.detail(id: id))
        }
    }

    let container = Container()
    let coordinator = Coordinator<TestRoute>(root: .home)
    let dataService = MockDataService()
    let viewModel: TestViewModel

    init() {
        viewModel = TestViewModel(router: coordinator, dataService: dataService)
    }

    // MARK: - DI Integration

    @Test func serviceRegistrationResolvesSameInstance() {
        container.register(instance: self.dataService)
        let resolved: MockDataService = container.resolve()
        #expect(resolved === dataService)
    }

    @Test func coordinatorCanBeRegisteredAndResolved() {
        container.register(instance: self.coordinator)
        let resolved: Coordinator<TestRoute> = container.resolve()
        #expect(resolved === coordinator)
    }

    @Test func moduleAssemblyRegistersFeatureService() {
        final class TestFeatureModule: DependencyModule {
            let dataService: DataService
            init(dataService: DataService) { self.dataService = dataService }
            func register(in container: Container) {
                container.register(instance: self.dataService)
            }
        }

        container.register(modules: [TestFeatureModule(dataService: dataService)])
        let resolved: DataService = container.resolve()
        #expect(resolved === dataService)
    }

    // MARK: - ViewModel + Router

    @Test func viewModelNavigatesThroughRouter() {
        viewModel.navigateToDetail(id: 123)
        #expect(coordinator.mainStack.path == [.detail(id: 123)])

        viewModel.navigateToDetail(id: 2)
        #expect(coordinator.mainStack.path == [.detail(id: 123), .detail(id: 2)])
    }

    // MARK: - ViewModel + Data Service

    @Test func loadSuccessReachesContent() async {
        await viewModel.loadData().value
        #expect(viewModel.phase == .content)
        #expect(dataService.callCount == 1)
    }

    @Test func loadFailureSurfacesError() async {
        dataService.shouldFail = true
        await viewModel.loadData().value
        #expect(viewModel.currentError?.title == "Load Failed")
    }

    /// AF-05: the exact call a `ScreenContainer` content closure makes (`send(.loadData)`)
    /// — `handle(_:)` is a fire-and-forget `Void`, so the test polls observable state
    /// instead of awaiting a `Task`, the same way a UI test would.
    @Test func handleLoadDataReachesContentThroughTheSingleEntryPoint() async throws {
        viewModel.handle(.loadData)
        try await waitUntil { viewModel.phase == .content }
        #expect(dataService.callCount == 1)
    }

    @Test func handleNavigateToDetailPushesThroughTheSingleEntryPoint() {
        viewModel.handle(.navigateToDetail(id: 7))
        #expect(coordinator.mainStack.path == [.detail(id: 7)])
    }

    @Test func retryAfterFailureRecovers() async throws {
        dataService.shouldFail = true
        await viewModel.loadData().value
        #expect(viewModel.hasError)

        // El retry relanza performLoad internamente (no expone su Task): waitUntil.
        dataService.shouldFail = false
        viewModel.currentError?.retry?()
        try await waitUntil { viewModel.phase == .content }
        #expect(viewModel.phase == .content)
    }

    // MARK: - Full Flows

    @Test func loadDataThenNavigate() async {
        await viewModel.loadData().value

        viewModel.navigateToDetail(id: 42)
        #expect(coordinator.mainStack.path == [.detail(id: 42)])
    }

    @Test func errorAlertAndNavigationCoexist() async throws {
        dataService.shouldFail = true
        await viewModel.loadData().value

        viewModel.navigateToDetail(id: 100)
        #expect(viewModel.hasError)
        #expect(coordinator.mainStack.path == [.detail(id: 100)])

        let error = try #require(viewModel.currentError)
        viewModel.showAlert(.info(title: error.title, message: error.message))
        #expect(viewModel.alert != nil)
    }

    @Test func stateAndNavigationInterleave() {
        viewModel.setLoading()
        viewModel.showAlert(.info(title: "Wait", message: "Loading"))
        #expect(viewModel.isLoading)
        #expect(viewModel.alert != nil)

        viewModel.dismissAlert()
        viewModel.setContent()
        viewModel.navigateToDetail(id: 1)

        #expect(viewModel.alert == nil)
        #expect(viewModel.isContent)
        #expect(coordinator.mainStack.path == [.detail(id: 1)])

        coordinator.present(.settings, as: .sheet)
        #expect(coordinator.isSheetPresented)

        coordinator.dismiss()
        #expect(coordinator.activeLayer == .main)
    }

    // MARK: - Flow Lifecycle (child container per flow)

    /// A feature flow owns a child container: what it registers as `.singleton` is shared
    /// for the life of the flow, and a new flow gets a new container — nothing to destroy.
    @Test func featureFlowChildContainerLifecycle() {
        let firstFlow = Container(parent: container)
        firstFlow.register(MockDataService.self) { _ in MockDataService() }

        let service1: MockDataService = firstFlow.resolve()
        let service2: MockDataService = firstFlow.resolve()
        #expect(service1 === service2)

        let secondFlow = Container(parent: container)
        secondFlow.register(MockDataService.self) { _ in MockDataService() }
        let service3: MockDataService = secondFlow.resolve()
        #expect(service1 !== service3)

        // The app-level container never saw the flow's registrations.
        #expect(!container.canResolve(MockDataService.self))
    }

    // MARK: - Constructor Injection

    @Test func constructorInjectionKeepsProvidedDependencies() async {
        let testRouter = Coordinator<TestRoute>(root: .home)
        let testService = MockDataService()

        let vm = TestViewModel(router: testRouter, dataService: testService)
        #expect(vm.router === testRouter)
        #expect(vm.dataService === testService)

        await vm.loadData().value
        #expect(vm.phase == .content)
    }
}
