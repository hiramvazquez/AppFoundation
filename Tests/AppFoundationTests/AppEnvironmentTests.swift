import Testing
import Foundation
@testable import AppFoundation

@Suite("AppEnvironment")
struct AppEnvironmentTests {
    @Test func testRunnerIsNotTestFlight() {
        // El runner de tests no tiene sandboxReceipt: el check legacy (anotado como
        // deprecado en iOS 18) debe responder false, no crashear ni asumir true.
        #expect(!AppEnvironment.isTestFlight)
    }

    @Test func debugAndReleaseAreMutuallyExclusive() {
        #expect(AppEnvironment.isDebug != AppEnvironment.isRelease)
        #expect(AppEnvironment.isDevice != AppEnvironment.isSimulator)
    }

    @Test func productionRequiresReleaseAndNoTestFlight() {
        #expect(AppEnvironment.isProduction == (AppEnvironment.isRelease && !AppEnvironment.isTestFlight))
    }

    @Test func fullVersionComposesVersionAndBuild() {
        #expect(AppEnvironment.fullVersion == "\(AppEnvironment.appVersion) (\(AppEnvironment.buildNumber))")
    }
}
