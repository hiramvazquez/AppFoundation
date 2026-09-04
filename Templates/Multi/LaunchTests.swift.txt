import XCTest

/// Arranque offline (`UI_TEST_OFFLINE`, horneado en el esquema por xcodegen —
/// `project.yml`): confirma que la app llega a pantalla sin depender de red real. Cuando
/// el primer feature exista, sustituye la comprobación del placeholder por una de su UI.
final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesToPlaceholder() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}
