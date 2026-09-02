import Testing
import SwiftUI
@testable import AppFoundation

// README «Recommended project flow §1» and «Dependency injection», copied as they appear
// in the README so that any drift between docs and API fails to compile here.
//
// Two deliberate deviations, because this is a test target:
// - `@main` is not applied to `MyApp` (a test bundle has no entry point), and nothing
//   here calls `Container.shared.register` — the suite never mutates the global.
// - `Profile` comes from README §5 (it is declared there, used in §1).

// MARK: - §1 Register dependencies

struct Profile {
    let name: String
}

protocol ProfileRepository {
    func fetchProfile() async throws -> Profile
}

final class LiveProfileRepository: ProfileRepository {
    func fetchProfile() async throws -> Profile {
        Profile(name: "Hiram")
    }
}

final class ProfileSyncService {
    let repository: ProfileRepository
    init(repository: ProfileRepository) { self.repository = repository }
}

struct ProfileModule: DependencyModule {
    func register(in container: Container) {
        container.register(ProfileRepository.self) { _ in LiveProfileRepository() }
        // The factory receives the container it was registered in: resolve dependencies
        // from it, never from a global.
        container.register(ProfileSyncService.self) { c in
            ProfileSyncService(repository: c.resolve())
        }
    }
}

struct MyApp: App {
    init() {
        Container.shared.register(modules: [ProfileModule()])
    }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}

final class MockProfileRepository: ProfileRepository {
    func fetchProfile() async throws -> Profile {
        Profile(name: "Mock")
    }
}

// MARK: - «Dependency injection» — one child container per flow

final class CheckoutCart {
    var items: [String] = []
}

final class CheckoutViewModel: BaseViewModel {
    let cart: CheckoutCart
    let repository: ProfileRepository

    init(cart: CheckoutCart, repository: ProfileRepository) {
        self.cart = cart
        self.repository = repository
        super.init()
    }
}

func makeCheckoutContainer(parent: Container = .shared) -> Container {
    let checkout = Container(parent: parent)
    // Shared by every screen of the flow.
    checkout.register(CheckoutCart.self) { _ in CheckoutCart() }
    // One per screen; `repository` falls back to the parent.
    checkout.register(CheckoutViewModel.self, lifecycle: .transient) { c in
        CheckoutViewModel(cart: c.resolve(), repository: c.resolve())
    }
    return checkout
}

// MARK: - «Dependency injection» — Environment for Views, @Inject for leaf classes

protocol AnalyticsService {
    func log(_ event: String)
}

struct NoopAnalytics: AnalyticsService {
    func log(_ event: String) {}
}

extension EnvironmentValues {
    @Entry var analytics: AnalyticsService = NoopAnalytics()
}

struct ProfileView: View {
    @Environment(\.analytics) private var analytics

    var body: some View {
        Text("Profile").onAppear { analytics.log("profile_shown") }
    }
}

// At the root, from the composition root:
struct RootView: View {
    var body: some View {
        ProfileView().environment(\.analytics, Container.shared.resolve())
    }
}

final class AnalyticsAdapter {
    @Inject private var analytics: AnalyticsService

    func track(_ event: String) {
        analytics.log(event)
    }
}

// MARK: - The examples not only compile: they behave as the README says

@Suite("README examples compile — Dependency injection")
struct ReadmeDIExamplesTests {
    @Test func moduleRegistersAbstractionAndFactoryResolvesFromItsContainer() {
        let container = Container()
        container.register(modules: [ProfileModule()])

        let repository: ProfileRepository = container.resolve()
        let sync: ProfileSyncService = container.resolve()
        #expect(repository is LiveProfileRepository)
        // `ProfileRepository` is not class-constrained; compare through the concrete
        // type to confirm the singleton is shared, not just same-typed.
        #expect((sync.repository as? LiveProfileRepository) === (repository as? LiveProfileRepository))
    }

    @Test func childContainerOverridesForTestsWithoutMutatingTheParent() async throws {
        let app = Container()
        app.register(modules: [ProfileModule()])

        let container = Container(parent: app)
        container.register(instance: MockProfileRepository(), as: ProfileRepository.self)

        let mocked: ProfileRepository = container.resolve()
        let live: ProfileRepository = app.resolve()
        #expect(try await mocked.fetchProfile().name == "Mock")
        #expect(try await live.fetchProfile().name == "Hiram")
    }

    @Test func checkoutFlowSharesTheCartAndBuildsOneViewModelPerScreen() {
        let app = Container()
        app.register(modules: [ProfileModule()])

        let checkout = makeCheckoutContainer(parent: app)
        let first: CheckoutViewModel = checkout.resolve()
        let second: CheckoutViewModel = checkout.resolve()

        #expect(first !== second)
        #expect(first.cart === second.cart)
        #expect(first.repository is LiveProfileRepository)
        #expect(!app.canResolve(CheckoutCart.self))
    }

    @Test func environmentDefaultAndInjectLeafBothCompileAgainstTheSameProtocol() {
        let container = Container()
        container.register(instance: NoopAnalytics(), as: AnalyticsService.self)

        let analytics: AnalyticsService = container.resolve()
        #expect(analytics is NoopAnalytics)
        #expect(EnvironmentValues().analytics is NoopAnalytics)
        _ = AnalyticsAdapter()
        _ = ProfileView()
        _ = RootView()
    }
}
