# AppFoundation

AppFoundation is a single Swift Package for new SwiftUI apps. It gives every project the same baseline for screen state, secondary activity handling, navigation, dependency injection, shell UI, and a few reusable utilities.

## What it includes

- **Architecture**
  - `BaseViewModel`
  - `ViewPhase`
  - `ActivityState`
  - `AlertState`
  - `BannerState`
  - `ScreenError`
- **Navigation**
  - `Router`
  - `Coordinator`
  - `CoordinatorView`
- **Dependency Injection**
  - `Container`
  - `DependencyModule`
  - `DependencyAssembler`
  - `@Inject`
- **UI**
  - `ScreenContainer` / `ScreenShell`
  - `CustomNavigationBar`
  - `NavigationBarItem`
- **Utilities**
  - `Debouncer`
  - `Throttler`
  - `WrappedError`
  - `AppEnvironment`

## Design rules

- One package for greenfield SwiftUI apps.
- Constructor injection first.
- `@Inject` only for edges where constructor injection is awkward.
- View models depend on `Router`, not on the concrete coordinator whenever possible.
- Primary screen state and secondary work are different concerns.

## Primary phase vs secondary activity

AppFoundation intentionally separates:

- `phase`: the main screen state
  - `.idle`
  - `.loading`
  - `.content`
  - `.empty`
  - `.error(ScreenError)`
- `activity`: transient work while content remains visible
  - `.none`
  - `.loading(.inline)`
  - `.loading(.overlay)`

Use `phase` for initial loads or full-screen failures.
Use `activity` for refresh, submit, pagination, sync, or background work that should not replace the content.

## Installation

Add the package locally or from your internal git server, then import:

```swift
import AppFoundation
```

## Recommended project flow

### 1. Register dependencies

```swift
import AppFoundation

protocol ProfileRepository {
    func fetchProfile() async throws -> Profile
}

final class LiveProfileRepository: ProfileRepository {
    func fetchProfile() async throws -> Profile {
        Profile(name: "Hiram")
    }
}

struct ProfileModule: DependencyModule {
    func register(in container: Container) {
        container.register(LiveProfileRepository() as ProfileRepository, lifecycle: .singleton)
    }
}

DependencyAssembler.shared.register([
    ProfileModule()
])
```

### 2. Define routes

```swift
enum AppRoute: Hashable {
    case home
    case profile
    case profileDetails(id: String)
}
```

### 3. Create the coordinator

```swift
@StateObject private var coordinator = Coordinator<AppRoute>(root: .home)

var body: some View {
    CoordinatorView(coordinator: coordinator) { route in
        switch route {
        case .home:
            HomeView(viewModel: HomeViewModel(router: coordinator))
        case .profile:
            ProfileView(viewModel: ProfileViewModel(
                repository: Container.shared.resolve(),
                router: coordinator
            ))
        case .profileDetails(let id):
            ProfileDetailsView(id: id)
        }
    }
}
```

### 4. Build a feature view model

```swift
import AppFoundation

struct Profile {
    let name: String
}

@MainActor
final class ProfileViewModel: BaseViewModel {
    @Published private(set) var profile: Profile?

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
        performLoad(successTransition: .preserveCurrentPhase) {
            let profile = try await repository.fetchProfile()
            self.profile = profile
            self.setContent()
        }
    }

    func refresh() {
        performActivity(style: .overlay) {
            let profile = try await repository.fetchProfile()
            self.profile = profile
            self.showBanner(.success("Profile updated"))
        }
    }

    func openDetails() {
        router.push(.profileDetails(id: "42"))
    }
}
```

### 5. Render with `ScreenContainer`

```swift
struct ProfileView: View {
    @StateObject var viewModel: ProfileViewModel

    var body: some View {
        ScreenContainer(
            viewModel: viewModel,
            navigation: .withBack(title: "Profile") {
                // Usually delegated back to router/coordinator owner
            }
        ) {
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
        .onAppear {
            viewModel.onAppear()
        }
    }
}
```

## `BaseViewModel` guidance

### For initial load

```swift
performLoad {
    let data = try await service.fetch()
    self.items = data
}
```

### When the work decides the next phase itself

```swift
performLoad(successTransition: .preserveCurrentPhase) {
    let items = try await service.fetch()
    self.items = items
    if items.isEmpty {
        self.setEmpty()
    } else {
        self.setContent()
    }
}
```

### For secondary work

```swift
performActivity(style: .inline) {
    try await service.sync()
}
```

## Dependency injection guidance

Preferred:

```swift
init(repository: ProfileRepository, router: any Router<AppRoute>) {
    self.repository = repository
    self.router = router
    super.init()
}
```

Use `@Inject` only when constructor injection would create more friction than value:

```swift
final class AnalyticsAdapter {
    @Inject private var environment: AppEnvironment
}
```

## Notes

- `ScreenContainer` is the public shell type.
- `ScreenShell` is kept as an alias for readability.
- `load(...)` still exists for backwards compatibility, but `performLoad(...)` is the preferred API.
- `performActivity(...)` is the preferred path for refresh, submit, and background work.
