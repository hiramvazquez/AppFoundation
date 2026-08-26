import XCTest
@testable import AppFoundation

@MainActor
final class CoordinatorTests: XCTestCase {
    // MARK: - Test Routes

    enum TestRoute: Hashable {
        case home
        case profile
        case settings
        case detail(id: Int)
    }

    // MARK: - Setup & Teardown

    var coordinator: Coordinator<TestRoute>!

    override func setUp() {
        super.setUp()
        coordinator = Coordinator(root: .home)
    }

    override func tearDown() {
        coordinator = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitWithRoot() {
        // Given/When
        let coordinator = Coordinator<TestRoute>(root: .home)

        // Then
        XCTAssertEqual(coordinator.mainStack.root, .home)
        XCTAssertTrue(coordinator.mainStack.path.isEmpty)
        XCTAssertTrue(coordinator.isAtRoot)
    }

    // MARK: - Push Tests

    func testPush_OnMainLayer() {
        // When
        coordinator.push(.profile)

        // Then
        XCTAssertEqual(coordinator.mainStack.path, [.profile])
        XCTAssertFalse(coordinator.isAtRoot)
    }

    func testPush_Multiple_OnMainLayer() {
        // When
        coordinator.push(.profile)
        coordinator.push(.settings)

        // Then
        XCTAssertEqual(coordinator.mainStack.path, [.profile, .settings])
    }

    func testPush_WithDetail() {
        // When
        coordinator.push(.detail(id: 123))

        // Then
        XCTAssertEqual(coordinator.mainStack.path, [.detail(id: 123)])
    }

    func testPush_OnSheet() {
        // Given
        coordinator.present(.settings, as: .sheet)

        // When
        coordinator.push(.profile)

        // Then
        XCTAssertEqual(coordinator.sheetStack?.path, [.profile])
        XCTAssertEqual(coordinator.mainStack.path, [])
    }

    func testPush_OnFullScreenCover() {
        // Given
        coordinator.present(.settings, as: .fullScreenCover)

        // When
        coordinator.push(.profile)

        // Then
        XCTAssertEqual(coordinator.fullScreenStack?.path, [.profile])
        XCTAssertEqual(coordinator.mainStack.path, [])
    }

    // MARK: - Pop Tests

    func testPop_FromMainStack() {
        // Given
        coordinator.push(.profile)
        coordinator.push(.settings)

        // When
        coordinator.pop()

        // Then
        XCTAssertEqual(coordinator.mainStack.path, [.profile])
    }

    func testPop_EmptyStack_DoesNothing() {
        // When
        coordinator.pop()

        // Then
        XCTAssertTrue(coordinator.mainStack.path.isEmpty)
        XCTAssertEqual(coordinator.mainStack.root, .home)
    }

    func testPop_FromSheet() {
        // Given
        coordinator.present(.settings, as: .sheet)
        coordinator.push(.profile)

        // When
        coordinator.pop()

        // Then
        XCTAssertTrue(coordinator.sheetStack?.path.isEmpty ?? false)
    }

    // MARK: - PopToRoot Tests

    func testPopToRoot_ClearsMainStack() {
        // Given
        coordinator.push(.profile)
        coordinator.push(.settings)

        // When
        coordinator.popToRoot()

        // Then
        XCTAssertTrue(coordinator.mainStack.path.isEmpty)
        XCTAssertEqual(coordinator.mainStack.root, .home)
        XCTAssertTrue(coordinator.isAtRoot)
    }

    func testPopToRoot_AlreadyAtRoot() {
        // When
        coordinator.popToRoot()

        // Then
        XCTAssertTrue(coordinator.mainStack.path.isEmpty)
        XCTAssertTrue(coordinator.isAtRoot)
    }

    func testPopToRoot_OnSheet() {
        // Given
        coordinator.present(.settings, as: .sheet)
        coordinator.push(.profile)

        // When
        coordinator.popToRoot()

        // Then
        XCTAssertTrue(coordinator.sheetStack?.path.isEmpty ?? false)
    }

    // MARK: - PopTo Tests

    func testPopTo_ExistingRoute() {
        // Given
        coordinator.push(.profile)
        coordinator.push(.settings)
        coordinator.push(.detail(id: 1))

        // When
        coordinator.popTo(.profile)

        // Then
        XCTAssertEqual(coordinator.mainStack.path, [.profile])
    }

    func testPopTo_NonExistingRoute_DoesNothing() {
        // Given
        coordinator.push(.profile)

        // When
        coordinator.popTo(.settings)

        // Then
        XCTAssertEqual(coordinator.mainStack.path, [.profile])
    }

    func testPopTo_Root() {
        // Given
        coordinator.push(.profile)
        coordinator.push(.settings)

        // When
        coordinator.popTo(.home)

        // Then
        XCTAssertTrue(coordinator.mainStack.path.isEmpty)
    }

    // MARK: - Present Sheet Tests

    func testPresentSheet() {
        // When
        coordinator.present(.settings, as: .sheet)

        // Then
        XCTAssertTrue(coordinator.isSheetPresented)
        XCTAssertEqual(coordinator.sheetStack?.root, .settings)
        XCTAssertFalse(coordinator.isAtRoot)
    }

    func testPresentSheet_MultipleRoutes() {
        // Given
        coordinator.present(.settings, as: .sheet)

        // When
        coordinator.push(.profile)

        // Then
        XCTAssertEqual(coordinator.sheetStack?.path, [.profile])
        XCTAssertEqual(coordinator.sheetStack?.root, .settings)
    }

    func testPresentSheet_ReplacePreviousSheet() {
        // Given
        coordinator.present(.settings, as: .sheet)

        // When
        coordinator.present(.profile, as: .sheet)

        // Then
        XCTAssertTrue(coordinator.isSheetPresented)
        XCTAssertEqual(coordinator.sheetStack?.root, .profile)
        XCTAssertTrue(coordinator.sheetStack?.path.isEmpty ?? true)
    }

    // MARK: - Present FullScreenCover Tests

    func testPresentFullScreenCover() {
        // When
        coordinator.present(.settings, as: .fullScreenCover)

        // Then
        XCTAssertTrue(coordinator.isFullScreenPresented)
        XCTAssertEqual(coordinator.fullScreenStack?.root, .settings)
        XCTAssertFalse(coordinator.isAtRoot)
    }

    func testPresentFullScreenCover_DoesNotAffectSheet() {
        // When
        coordinator.present(.settings, as: .fullScreenCover)

        // Then
        XCTAssertTrue(coordinator.isFullScreenPresented)
        XCTAssertFalse(coordinator.isSheetPresented)
    }

    // MARK: - Dismiss Tests

    func testDismissSheet() {
        // Given
        coordinator.present(.settings, as: .sheet)
        XCTAssertTrue(coordinator.isSheetPresented)

        // When
        coordinator.dismiss()

        // Then
        XCTAssertFalse(coordinator.isSheetPresented)
        XCTAssertNil(coordinator.sheetStack)
        XCTAssertTrue(coordinator.isAtRoot)
    }

    func testDismissFullScreenCover() {
        // Given
        coordinator.present(.settings, as: .fullScreenCover)
        XCTAssertTrue(coordinator.isFullScreenPresented)

        // When
        coordinator.dismiss()

        // Then
        XCTAssertFalse(coordinator.isFullScreenPresented)
        XCTAssertNil(coordinator.fullScreenStack)
        XCTAssertTrue(coordinator.isAtRoot)
    }

    func testDismiss_DismissesOnlyTopMostModal() {
        // Given
        coordinator.present(.settings, as: .fullScreenCover)
        coordinator.present(.profile, as: .sheet)

        // When
        coordinator.dismiss()

        // Then
        XCTAssertFalse(coordinator.isSheetPresented)
        XCTAssertTrue(coordinator.isFullScreenPresented)
    }

    func testDismiss_OnMainLayer_DoesNothing() {
        // When
        coordinator.dismiss()

        // Then
        XCTAssertTrue(coordinator.isAtRoot)
    }

    // MARK: - SetRoot Tests

    func testSetRoot() {
        // Given
        coordinator.push(.profile)
        coordinator.push(.settings)

        // When
        coordinator.setRoot(.home)

        // Then
        XCTAssertEqual(coordinator.mainStack.root, .home)
        XCTAssertTrue(coordinator.mainStack.path.isEmpty)
        XCTAssertTrue(coordinator.isAtRoot)
    }

    func testSetRoot_ChangesRoute() {
        // When
        coordinator.setRoot(.profile)

        // Then
        XCTAssertEqual(coordinator.mainStack.root, .profile)
    }

    // MARK: - SetStack Tests

    func testSetStack() {
        // When
        coordinator.setStack([.profile, .settings, .detail(id: 1)])

        // Then
        XCTAssertEqual(coordinator.mainStack.path, [.profile, .settings, .detail(id: 1)])
    }

    func testSetStack_EmptyArray() {
        // Given
        coordinator.push(.profile)

        // When
        coordinator.setStack([])

        // Then
        XCTAssertTrue(coordinator.mainStack.path.isEmpty)
    }

    // MARK: - ActiveLayer Tests

    func testActiveLayer_Main() {
        // When/Then
        XCTAssertEqual(coordinator.activeLayer, .main)
    }

    func testActiveLayer_Sheet() {
        // When
        coordinator.present(.settings, as: .sheet)

        // Then
        XCTAssertEqual(coordinator.activeLayer, .sheet)
    }

    func testActiveLayer_FullScreenCover() {
        // When
        coordinator.present(.settings, as: .fullScreenCover)

        // Then
        XCTAssertEqual(coordinator.activeLayer, .fullScreenCover)
    }

    func testActiveLayer_FullScreenPriority() {
        // Given
        coordinator.present(.settings, as: .sheet)

        // When
        coordinator.present(.profile, as: .fullScreenCover)

        // Then
        XCTAssertEqual(coordinator.activeLayer, .fullScreenCover)
    }

    // MARK: - IsAtRoot Tests

    func testIsAtRoot_Initial() {
        // When/Then
        XCTAssertTrue(coordinator.isAtRoot)
    }

    func testIsAtRoot_AfterPush() {
        // When
        coordinator.push(.profile)

        // Then
        XCTAssertFalse(coordinator.isAtRoot)
    }

    func testIsAtRoot_AfterPresent() {
        // When
        coordinator.present(.settings, as: .sheet)

        // Then
        XCTAssertFalse(coordinator.isAtRoot)
    }

    func testIsAtRoot_AfterDismiss() {
        // Given
        coordinator.present(.settings, as: .sheet)

        // When
        coordinator.dismiss()

        // Then
        XCTAssertTrue(coordinator.isAtRoot)
    }

    // MARK: - Router Protocol Conformance Tests

    func testRouterProtocolConformance_CanBeUsedAsAnyRouter() {
        // Given
        let router: any Router<TestRoute> = coordinator

        // When
        router.push(.profile)
        router.push(.settings)

        // Then
        XCTAssertEqual(coordinator.mainStack.path, [.profile, .settings])
    }

    func testRouterProtocol_PushPopWorkCorrectly() {
        // Given
        let router: any Router<TestRoute> = coordinator

        // When
        router.push(.profile)
        router.push(.settings)
        router.pop()

        // Then
        XCTAssertEqual(coordinator.mainStack.path, [.profile])
    }

    // MARK: - Complex Navigation Scenarios

    func testComplexScenario_MainToSheetWithNavigation() {
        // Given/When
        coordinator.push(.profile)
        coordinator.present(.settings, as: .sheet)
        coordinator.push(.detail(id: 1))

        // Then
        XCTAssertEqual(coordinator.mainStack.path, [.profile])
        XCTAssertEqual(coordinator.sheetStack?.path, [.detail(id: 1)])
        XCTAssertEqual(coordinator.activeLayer, .sheet)
    }

    func testComplexScenario_FullScreenThenSheet() {
        // When
        coordinator.present(.settings, as: .fullScreenCover)
        coordinator.push(.profile)

        // Dismiss fullscreen and present sheet
        coordinator.dismiss()
        coordinator.present(.detail(id: 1), as: .sheet)

        // Then
        XCTAssertFalse(coordinator.isFullScreenPresented)
        XCTAssertTrue(coordinator.isSheetPresented)
        XCTAssertEqual(coordinator.activeLayer, .sheet)
    }

    func testComplexScenario_DeepStackNavigation() {
        // When
        coordinator.push(.profile)
        coordinator.push(.settings)
        coordinator.push(.detail(id: 1))
        coordinator.push(.detail(id: 2))
        coordinator.push(.detail(id: 3))

        // Then
        XCTAssertEqual(coordinator.mainStack.path.count, 5)

        // When - pop to middle
        coordinator.popTo(.detail(id: 1))

        // Then
        XCTAssertEqual(coordinator.mainStack.path, [.profile, .settings, .detail(id: 1)])
    }

    func testComplexScenario_NavigationStackTracking() {
        // When
        coordinator.push(.profile)
        XCTAssertFalse(coordinator.isAtRoot)

        coordinator.push(.settings)
        XCTAssertEqual(coordinator.mainStack.path.count, 2)

        coordinator.popToRoot()
        XCTAssertTrue(coordinator.isAtRoot)

        // When - Navigate via modal
        coordinator.present(.profile, as: .sheet)
        XCTAssertFalse(coordinator.isAtRoot)

        coordinator.dismiss()
        XCTAssertTrue(coordinator.isAtRoot)
    }

    // MARK: - Published Properties Tests

    func testIsAtRootPublishes() {
        // Given
        var isAtRootValues: [Bool] = []
        let cancellable = coordinator.$isAtRoot.sink { value in
            isAtRootValues.append(value)
        }

        // When
        coordinator.push(.profile)

        // Then
        XCTAssertGreaterThanOrEqual(isAtRootValues.count, 2)
        XCTAssertTrue(isAtRootValues[0]) // Initial
        XCTAssertFalse(isAtRootValues[1]) // After push

        cancellable.cancel()
    }

    func testSheetStatePublishes() {
        // Given
        var isSheetPresentedValues: [Bool] = []
        let cancellable = coordinator.$isSheetPresented.sink { value in
            isSheetPresentedValues.append(value)
        }

        // When
        coordinator.present(.settings, as: .sheet)

        // Then
        XCTAssertGreaterThanOrEqual(isSheetPresentedValues.count, 2)
        XCTAssertEqual(isSheetPresentedValues.last, true)

        cancellable.cancel()
    }
}
