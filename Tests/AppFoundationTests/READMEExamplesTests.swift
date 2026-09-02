import SwiftUI
import Testing

@testable import AppFoundation

// README «Recommended project flow §2-6» and «BaseViewModel guidance», copied as they
// appear in the README so that any drift between docs and API fails to compile here.
//
// `ReadmeDIExamplesTests.swift` already covers §1 and «Dependency injection» at the top
// level of the test target (it declares `Profile`, `ProfileRepository`,
// `LiveProfileRepository`, `ProfileSyncService`, `ProfileModule`) — §5 below reuses those
// exact types, the same way the README itself does across sections. Everything that would
// otherwise collide with a type already declared there (the README repeats `ProfileView`
// with a different body in §6) is nested inside `READMEProjectFlowExamples`, mirroring how
// `IntegrationTests.swift` scopes its own fixtures.

private enum READMEProjectFlowExamples {
    // MARK: - §2 Define routes

    enum AppRoute: Hashable {
        case home
        case profile
        case profileDetails(id: String)
    }

    // MARK: - §4 Deep links

    // `Equatable` here is a test-only addition (not in the README) so the assertion below
    // can compare the parsed link directly instead of pattern-matching it.
    enum AppDeepLink: DeepLinkType, Equatable {
        case profile(id: String)

        static func parse(_ url: URL) -> AppDeepLink? {
            let components = url.pathComponents
            guard let index = components.firstIndex(of: "profile"), components.count > index + 1 else {
                return nil
            }
            return .profile(id: components[index + 1])
        }
    }

    // MARK: - §5 Build a feature view model

    final class ProfileViewModel: BaseViewModel {
        private(set) var profile: Profile?

        private let repository: ProfileRepository
        private let router: any Router<AppRoute>

        init(
            repository: ProfileRepository,
            router: any Router<AppRoute>
        ) {
            self.repository = repository
            self.router = router
            super.init()
        }

        func onAppear() {
            performLoad(successTransition: .preserveCurrentPhase) { vm in
                let profile = try await vm.repository.fetchProfile()
                vm.profile = profile
                vm.setContent()
            }
        }

        func refresh() {
            performActivity(style: .overlay) { vm in
                let profile = try await vm.repository.fetchProfile()
                vm.profile = profile
                vm.showBanner(.success("Profile updated"))
            }
        }

        func openDetails() {
            router.push(.profileDetails(id: "42"))
        }
    }

    // MARK: - §6 Render with ScreenContainer

    struct ProfileView: View {
        let viewModel: ProfileViewModel

        var body: some View {
            ScreenContainer(viewModel: viewModel) {
                VStack(spacing: 20) {
                    if let profile = viewModel.profile {
                        Text(profile.name)
                            .font(.title)
                    }

                    Button("Refresh") {
                        viewModel.refresh()
                    }

                    Button("Open details") {
                        viewModel.openDetails()
                    }
                }
                .padding()
            }
            .navigationTitle("Profile")
            .onAppear {
                viewModel.onAppear()
            }
        }
    }

    // MARK: - #6 Opt-in custom navigation bar

    struct ProfileContent: View {
        var body: some View { Text("Profile") }
    }

    struct CustomBarProfileView: View {
        let viewModel: ProfileViewModel

        var body: some View {
            ScreenContainer(
                viewModel: viewModel,
                chrome: .custom(.withBack(title: "Profile") {})
            ) {
                ProfileContent()
            }
        }
    }

    // MARK: - «Errors» — pluggable loading/error/empty appearances

    struct BrandErrorStyle: ErrorViewStyle {
        func makeBody(configuration: ErrorConfiguration) -> some View {
            VStack {
                Text(configuration.error.title).font(.headline)
                Text(configuration.error.message)
                if let retry = configuration.error.retry {
                    Button("Try again", action: retry)
                }
            }
        }
    }
}

// MARK: - The examples not only compile: they behave as the README says

@Suite("README examples compile — Recommended project flow (§2-6)")
struct READMEProjectFlowTests {
    private typealias Fixtures = READMEProjectFlowExamples

    @Test func onAppearLoadsProfileAndSetsContent() async throws {
        let coordinator = Coordinator<Fixtures.AppRoute>(root: .home)
        let viewModel = Fixtures.ProfileViewModel(repository: LiveProfileRepository(), router: coordinator)

        viewModel.onAppear()
        try await waitUntil { viewModel.phase == .content }

        #expect(viewModel.profile?.name == "Hiram")
    }

    @Test func openDetailsPushesRouteThroughRouter() {
        let coordinator = Coordinator<Fixtures.AppRoute>(root: .home)
        let viewModel = Fixtures.ProfileViewModel(repository: LiveProfileRepository(), router: coordinator)

        viewModel.openDetails()

        #expect(coordinator.mainStack.path == [.profileDetails(id: "42")])
    }

    @Test func refreshUpdatesProfileAndShowsBanner() async throws {
        let coordinator = Coordinator<Fixtures.AppRoute>(root: .home)
        let viewModel = Fixtures.ProfileViewModel(repository: LiveProfileRepository(), router: coordinator)

        viewModel.refresh()
        try await waitUntil { viewModel.profile != nil }

        #expect(viewModel.profile?.name == "Hiram")
        #expect(viewModel.banner != nil)
    }

    @Test func deepLinkParsesProfileID() {
        let url = URL(string: "myapp://app/profile/42")!
        let link = Fixtures.AppDeepLink.parse(url)
        #expect(link == .profile(id: "42"))
    }

    @Test func deepLinkHandledByCoordinatorSetsStack() {
        let coordinator = Coordinator<Fixtures.AppRoute>(root: .home)
        let handled = coordinator.handle(URL(string: "myapp://app/profile/42")!, as: Fixtures.AppDeepLink.self) {
            link in
            switch link {
            case .profile(let id): .setStack([.profile, .profileDetails(id: id)])
            }
        }
        #expect(handled)
        #expect(coordinator.mainStack.path == [.profile, .profileDetails(id: "42")])
    }

    @Test func screenContainerViewsCompileAndCanBeInstantiated() {
        let coordinator = Coordinator<Fixtures.AppRoute>(root: .home)
        let viewModel = Fixtures.ProfileViewModel(repository: LiveProfileRepository(), router: coordinator)

        _ = Fixtures.ProfileView(viewModel: viewModel)
        _ = Fixtures.CustomBarProfileView(viewModel: viewModel)
        _ = ScreenContainer(viewModel: viewModel) { Fixtures.ProfileContent() }
            .errorViewStyle(Fixtures.BrandErrorStyle())
    }
}

// MARK: - «`BaseViewModel` guidance» — performLoad/load variants

private final class GuidanceViewModel: BaseViewModel {
    var items: [String] = []
    let service = GuidanceService()
}

private struct GuidanceService {
    func fetch() async throws -> [String] { ["a", "b"] }
    func sync() async throws {}
}

@Suite("README examples compile — BaseViewModel guidance")
struct READMEBaseViewModelGuidanceTests {
    @Test("For initial load")
    func forInitialLoad() async {
        let viewModel = GuidanceViewModel()
        await viewModel.performLoad { vm in
            let data = try await vm.service.fetch()
            vm.items = data
        }
        .value

        #expect(viewModel.phase == .content)
        #expect(viewModel.items == ["a", "b"])
    }

    @Test("When the work decides the next phase itself")
    func workDecidesNextPhase() async {
        let viewModel = GuidanceViewModel()
        await viewModel.performLoad(successTransition: .preserveCurrentPhase) { vm in
            let items = try await vm.service.fetch()
            vm.items = items
            if items.isEmpty {
                vm.setEmpty()
            } else {
                vm.setContent()
            }
        }
        .value

        #expect(viewModel.phase == .content)
    }

    @Test("For secondary work")
    func forSecondaryWork() async {
        let viewModel = GuidanceViewModel()
        await viewModel.performActivity(style: .inline) { vm in
            try await vm.service.sync()
        }
        .value

        #expect(viewModel.activity == .none)
    }

    @Test("Structured variant: cancellation follows the view, not deinit")
    func structuredVariant() async {
        let viewModel = GuidanceViewModel()
        await viewModel.load { vm in
            vm.items = try await vm.service.fetch()
        }

        #expect(viewModel.items == ["a", "b"])
    }

    @Test("Deterministic tests: await the returned Task")
    func deterministicTests() async {
        let viewModel = GuidanceViewModel()
        await viewModel.performLoad { vm in vm.items = try await vm.service.fetch() }.value
        #expect(viewModel.phase == .content)
    }
}
