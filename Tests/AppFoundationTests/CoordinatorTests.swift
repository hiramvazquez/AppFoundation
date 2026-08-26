import Testing
@testable import AppFoundation

@Suite("Coordinator")
struct CoordinatorTests {
    enum TestRoute: Hashable {
        case home
        case profile
        case settings
        case detail(id: Int)
    }

    let coordinator = Coordinator<TestRoute>(root: .home)

    // MARK: - Initialization

    @Test func initWithRoot() {
        #expect(coordinator.mainStack.root == .home)
        #expect(coordinator.mainStack.path.isEmpty)
        #expect(coordinator.isAtRoot)
    }

    // MARK: - Push

    @Test func pushOnMainLayer() {
        coordinator.push(.profile)
        #expect(coordinator.mainStack.path == [.profile])
        #expect(!coordinator.isAtRoot)
    }

    @Test func pushMultipleOnMainLayer() {
        coordinator.push(.profile)
        coordinator.push(.settings)
        #expect(coordinator.mainStack.path == [.profile, .settings])
    }

    @Test func pushRouteWithPayload() {
        coordinator.push(.detail(id: 123))
        #expect(coordinator.mainStack.path == [.detail(id: 123)])
    }

    @Test func pushGoesToActiveSheetLayer() {
        coordinator.present(.settings, as: .sheet)
        coordinator.push(.profile)
        #expect(coordinator.sheetStack?.path == [.profile])
        #expect(coordinator.mainStack.path.isEmpty)
    }

    @Test func pushGoesToActiveFullScreenLayer() {
        coordinator.present(.settings, as: .fullScreenCover)
        coordinator.push(.profile)
        #expect(coordinator.fullScreenStack?.path == [.profile])
        #expect(coordinator.mainStack.path.isEmpty)
    }

    // MARK: - Pop

    @Test func popFromMainStack() {
        coordinator.push(.profile)
        coordinator.push(.settings)
        coordinator.pop()
        #expect(coordinator.mainStack.path == [.profile])
    }

    @Test func popOnEmptyStackDoesNothing() {
        coordinator.pop()
        #expect(coordinator.mainStack.path.isEmpty)
        #expect(coordinator.mainStack.root == .home)
    }

    @Test func popFromSheet() {
        coordinator.present(.settings, as: .sheet)
        coordinator.push(.profile)
        coordinator.pop()
        #expect(coordinator.sheetStack?.path.isEmpty == true)
    }

    // MARK: - PopToRoot

    @Test func popToRootClearsMainStack() {
        coordinator.push(.profile)
        coordinator.push(.settings)
        coordinator.popToRoot()
        #expect(coordinator.mainStack.path.isEmpty)
        #expect(coordinator.isAtRoot)
    }

    @Test func popToRootOnSheet() {
        coordinator.present(.settings, as: .sheet)
        coordinator.push(.profile)
        coordinator.popToRoot()
        #expect(coordinator.sheetStack?.path.isEmpty == true)
    }

    // MARK: - PopTo

    @Test func popToExistingRoute() {
        coordinator.push(.profile)
        coordinator.push(.settings)
        coordinator.push(.detail(id: 1))
        coordinator.popTo(.profile)
        #expect(coordinator.mainStack.path == [.profile])
    }

    @Test func popToNonExistingRouteDoesNothing() {
        coordinator.push(.profile)
        coordinator.popTo(.settings)
        #expect(coordinator.mainStack.path == [.profile])
    }

    @Test func popToRootRoute() {
        coordinator.push(.profile)
        coordinator.push(.settings)
        coordinator.popTo(.home)
        #expect(coordinator.mainStack.path.isEmpty)
    }

    // MARK: - Present / Dismiss

    @Test func presentSheet() {
        coordinator.present(.settings, as: .sheet)
        #expect(coordinator.isSheetPresented)
        #expect(coordinator.sheetStack?.root == .settings)
        #expect(!coordinator.isAtRoot)
    }

    @Test func presentSheetReplacesPreviousSheet() {
        coordinator.present(.settings, as: .sheet)
        coordinator.present(.profile, as: .sheet)
        #expect(coordinator.isSheetPresented)
        #expect(coordinator.sheetStack?.root == .profile)
        #expect(coordinator.sheetStack?.path.isEmpty == true)
    }

    @Test func presentFullScreenCover() {
        coordinator.present(.settings, as: .fullScreenCover)
        #expect(coordinator.isFullScreenPresented)
        #expect(coordinator.fullScreenStack?.root == .settings)
        #expect(!coordinator.isAtRoot)
    }

    @Test func dismissSheet() {
        coordinator.present(.settings, as: .sheet)
        coordinator.dismiss()
        #expect(!coordinator.isSheetPresented)
        #expect(coordinator.sheetStack == nil)
        #expect(coordinator.isAtRoot)
    }

    @Test func dismissFullScreenCover() {
        coordinator.present(.settings, as: .fullScreenCover)
        coordinator.dismiss()
        #expect(!coordinator.isFullScreenPresented)
        #expect(coordinator.fullScreenStack == nil)
        #expect(coordinator.isAtRoot)
    }

    @Test func dismissOnMainLayerDoesNothing() {
        coordinator.dismiss()
        #expect(coordinator.isAtRoot)
    }

    // MARK: - SetRoot / SetStack

    @Test func setRootClearsStacks() {
        coordinator.push(.profile)
        coordinator.push(.settings)
        coordinator.setRoot(.home)
        #expect(coordinator.mainStack.root == .home)
        #expect(coordinator.mainStack.path.isEmpty)
        #expect(coordinator.isAtRoot)
    }

    @Test func setRootChangesRoute() {
        coordinator.setRoot(.profile)
        #expect(coordinator.mainStack.root == .profile)
    }

    @Test func setStackReplacesPath() {
        coordinator.setStack([.profile, .settings, .detail(id: 1)])
        #expect(coordinator.mainStack.path == [.profile, .settings, .detail(id: 1)])
    }

    @Test func setStackWithEmptyArrayClearsPath() {
        coordinator.push(.profile)
        coordinator.setStack([])
        #expect(coordinator.mainStack.path.isEmpty)
    }

    // MARK: - ActiveLayer

    @Test func activeLayerTracksPresentation() {
        #expect(coordinator.activeLayer == .main)

        coordinator.present(.settings, as: .sheet)
        #expect(coordinator.activeLayer == .sheet)

        coordinator.dismiss()
        coordinator.present(.settings, as: .fullScreenCover)
        #expect(coordinator.activeLayer == .fullScreenCover)
    }

    // MARK: - IsAtRoot

    @Test func isAtRootLifecycle() {
        #expect(coordinator.isAtRoot)

        coordinator.push(.profile)
        #expect(!coordinator.isAtRoot)

        coordinator.popToRoot()
        #expect(coordinator.isAtRoot)

        coordinator.present(.profile, as: .sheet)
        #expect(!coordinator.isAtRoot)

        coordinator.dismiss()
        #expect(coordinator.isAtRoot)
    }

    // MARK: - Router Protocol Conformance

    @Test func coordinatorWorksThroughRouterProtocol() {
        let router: any Router<TestRoute> = coordinator
        router.push(.profile)
        router.push(.settings)
        router.pop()
        #expect(coordinator.mainStack.path == [.profile])
    }

    // MARK: - Complex Scenarios

    @Test func mainToSheetWithNavigation() {
        coordinator.push(.profile)
        coordinator.present(.settings, as: .sheet)
        coordinator.push(.detail(id: 1))

        #expect(coordinator.mainStack.path == [.profile])
        #expect(coordinator.sheetStack?.path == [.detail(id: 1)])
        #expect(coordinator.activeLayer == .sheet)
    }

    @Test func fullScreenThenSheet() {
        coordinator.present(.settings, as: .fullScreenCover)
        coordinator.push(.profile)
        coordinator.dismiss()
        coordinator.present(.detail(id: 1), as: .sheet)

        #expect(!coordinator.isFullScreenPresented)
        #expect(coordinator.isSheetPresented)
        #expect(coordinator.activeLayer == .sheet)
    }

    @Test func deepStackNavigationWithPopTo() {
        coordinator.push(.profile)
        coordinator.push(.settings)
        coordinator.push(.detail(id: 1))
        coordinator.push(.detail(id: 2))
        coordinator.push(.detail(id: 3))
        #expect(coordinator.mainStack.path.count == 5)

        coordinator.popTo(.detail(id: 1))
        #expect(coordinator.mainStack.path == [.profile, .settings, .detail(id: 1)])
    }
}

// MARK: - Fase 3.5: política de UNA capa modal (A5/A6/A7)

@Suite("Coordinator — capa modal única")
struct CoordinatorModalPolicyTests {
    enum TestRoute: Hashable {
        case home, profile, settings
        case detail(id: Int)
    }

    let coordinator = Coordinator<TestRoute>(root: .home)

    /// A5: presentar sobre un modal existente lo REEMPLAZA (política documentada).
    @Test func presentOverSheetReplacesWithFullScreenCover() {
        coordinator.present(.settings, as: .sheet)
        coordinator.push(.profile)

        coordinator.present(.detail(id: 1), as: .fullScreenCover)

        #expect(coordinator.isFullScreenPresented)
        #expect(!coordinator.isSheetPresented)
        #expect(coordinator.sheetStack == nil)
        #expect(coordinator.fullScreenStack?.root == .detail(id: 1))
        #expect(coordinator.fullScreenStack?.path.isEmpty == true)
        #expect(coordinator.activeLayer == .fullScreenCover)
    }

    @Test func presentOverFullScreenCoverReplacesWithSheet() {
        coordinator.present(.settings, as: .fullScreenCover)
        coordinator.present(.profile, as: .sheet)

        #expect(coordinator.isSheetPresented)
        #expect(!coordinator.isFullScreenPresented)
        #expect(coordinator.modal?.stack.root == .profile)
        #expect(coordinator.activeLayer == .sheet)
    }

    /// El estado nunca modela lo que SwiftUI no puede renderizar: jamás dos modales.
    @Test func modalStateIsAlwaysSingleLayer() {
        coordinator.present(.settings, as: .sheet)
        coordinator.present(.profile, as: .fullScreenCover)
        coordinator.present(.detail(id: 2), as: .sheet)

        #expect(coordinator.modal != nil)
        #expect((coordinator.isSheetPresented ? 1 : 0) + (coordinator.isFullScreenPresented ? 1 : 0) == 1)
    }

    /// A7: dismiss descarta el stack del modal — nada queda rancio para el siguiente.
    @Test func dismissDiscardsModalPath() {
        coordinator.present(.settings, as: .sheet)
        coordinator.push(.profile)
        coordinator.push(.detail(id: 3))

        coordinator.dismiss()
        #expect(coordinator.modal == nil)

        coordinator.present(.settings, as: .sheet)
        #expect(coordinator.modal?.stack.path.isEmpty == true)
    }

    /// setRoot resetea de verdad: main limpio Y modal fuera.
    @Test func setRootDismissesModal() {
        coordinator.push(.profile)
        coordinator.present(.settings, as: .sheet)

        coordinator.setRoot(.home)

        #expect(coordinator.modal == nil)
        #expect(coordinator.mainStack.path.isEmpty)
        #expect(coordinator.isAtRoot)
    }
}
