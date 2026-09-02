# AppFoundation

AppFoundation is a single Swift Package for new SwiftUI apps. It gives every project the same baseline for screen state, secondary activity handling, navigation, dependency injection, shell UI, and a few reusable utilities.

Requires **Swift 6.2** (tools), **iOS 17 / macOS 14**. The package builds with
`defaultIsolation(MainActor)` (Approachable Concurrency) and warnings as errors.

## What it includes

- **Architecture**
  - `BaseViewModel` (`@Observable`)
  - `ViewPhase` / `ActivityStyle` / `ActivityState`
  - `AlertState`
  - `BannerState` (real auto-dismiss)
  - `ScreenError`
- **Navigation**
  - `Router`
  - `Coordinator` (`@Observable`, single modal layer)
  - `CoordinatorView`
  - `DeepLinkType` / `DeepLinkAction` (connected to `Coordinator.handle`)
- **Dependency Injection**
  - `Container` (immutable `Container.shared`, child containers for overrides)
  - `DependencyModule` + `Container.register(modules:)`
  - `@Inject` (`@MainActor`)
- **UI**
  - `ScreenContainer`
  - `CustomNavigationBar`
  - `NavigationBarItem` (stable identity + semantic roles)
- **Utilities**
  - `Debouncer` / `Throttler` (`@MainActor` classes, injectable `any Clock<Duration>`)
  - `WrappedError` (`AppErrorConvertible`)
  - `AppEnvironment` (namespace `enum`)

All user-visible default strings ship localized (EN + ES) through
`Resources/Localizable.xcstrings`, a String Catalog; visible-copy parameters accept
`LocalizedStringResource`, so string literals localize through your app's catalog.

## Design rules

- One package for greenfield SwiftUI apps.
- Constructor injection first.
- `@Inject` only for edges where constructor injection is awkward.
- View models depend on `Router`, not on the concrete coordinator whenever possible.
- Primary screen state and secondary work are different concerns.
- Cancellation is part of the contract: `performLoad`/`performActivity` return their
  `Task`, a new load cancels the in-flight one, and a cancelled load never surfaces
  as an error.

## Primary phase vs secondary activity

AppFoundation intentionally separates:

- `phase`: the main screen state
  - `.idle`
  - `.loading(ActivityStyle)` — `.fullScreen`, `.inline`, or `.overlay`
  - `.content`
  - `.empty`
  - `.error(ScreenError)`
- `activity`: transient work while content remains visible
  - `.none`
  - `.loading(ActivityStyle)`

There is ONE activity presentation system (`ActivityStyle`) shared by both, and every
style renders something — `.inline` shows an inline indicator while content stays visible.

Use `phase` for initial loads or full-screen failures.
Use `activity` for refresh, submit, pagination, sync, or background work that should not replace the content.

## Errors: `AppErrorConvertible` is the source of user-facing messages

Conform your domain errors to `AppErrorConvertible` and `performLoad`/`performActivity`
surface *your* title and message; raw `localizedDescription` is only the last-resort
fallback for foreign errors. `WrappedError` already conforms.

```swift
enum ProfileError: Error, AppErrorConvertible {
    case notFound

    var screenError: ScreenError {
        ScreenError(title: "Profile unavailable", message: "Try again later.")
    }
}
```

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

Container.shared.register(modules: [
    ProfileModule()
])
```

`Container.shared` is a `static let` and can never be swapped. Tests and previews use
child containers, which shadow the parent without mutating it:

```swift
let container = Container(parent: .shared)
container.register(MockProfileRepository(), lifecycle: .singleton, as: ProfileRepository.self)
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
@State private var coordinator = Coordinator<AppRoute>(root: .home)

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

The coordinator models **one modal layer**: presenting while a modal is visible replaces
it (documented policy). Need modal-over-modal? Give the presented destination its own
`Coordinator` + `CoordinatorView`.

### 4. Deep links

```swift
enum AppDeepLink: DeepLinkType {
    case profile(id: String)

    static func parse(_ url: URL) -> AppDeepLink? {
        let components = url.pathComponents
        guard let index = components.firstIndex(of: "profile"), components.count > index + 1 else {
            return nil
        }
        return .profile(id: components[index + 1])
    }
}

// e.g. in your root view:
.onOpenURL { url in
    coordinator.handle(url, as: AppDeepLink.self) { link in
        switch link {
        case .profile(let id): .setStack([.profile, .profileDetails(id: id)])
        }
    }
}
```

### 5. Build a feature view model

```swift
import AppFoundation

struct Profile {
    let name: String
}

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
        performLoad(successTransition: .preserveCurrentPhase) {
            let profile = try await self.repository.fetchProfile()
            self.profile = profile
            self.setContent()
        }
    }

    func refresh() {
        performActivity(style: .overlay) {
            let profile = try await self.repository.fetchProfile()
            self.profile = profile
            self.showBanner(.success("Profile updated"))
        }
    }

    func openDetails() {
        router.push(.profileDetails(id: "42"))
    }
}
```

`BaseViewModel` is `@Observable`: stored properties in subclasses are tracked
automatically — no `@Published`, no `ObservableObject`.

### 6. Render with `ScreenContainer`

```swift
struct ProfileView: View {
    let viewModel: ProfileViewModel

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

Alerts present through the native `.alert` by default; banners auto-dismiss after their
duration and are announced to VoiceOver.

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

### Deterministic tests

Both helpers return their `Task` — await it instead of sleeping:

```swift
await viewModel.performLoad { try await repository.fetch() }.value
#expect(viewModel.phase == .content)
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
    @Inject private var analytics: AnalyticsService
}
```

`@Inject` is `@MainActor` and requires the type to be registered (it traps otherwise —
absence is not modelled). For `nonisolated` code, call `Container.shared.resolve()` /
`tryResolve()` explicitly.

## Notes

- `ScreenContainer` is the public shell type.
- `performLoad(...)` / `performActivity(...)` are the single async entry points
  (the legacy `load(...)` wrapper is gone).
- `Debouncer` and `Throttler` are `@MainActor final class`, not actors (audit AF-19):
  their state is only ever touched by the caller, so `debounce`/`throttle` run
  synchronously on the main actor — no `Task`, no `await` at the call site for
  `debounce`, no `@Sendable` operation. The clock is `any Clock<Duration>` and
  defaults to `ContinuousClock`; tests inject a manual clock for deterministic,
  sleep-free assertions. `deinit` cancels any in-flight work.
- `AppEnvironment` is a namespace `enum` (no state to instantiate) and does not
  offer an "is this running under tests or previews" flag (audit AF-20) — inject
  the behaviour you want in tests instead of asking the environment.
- Default strings live in `Resources/Localizable.xcstrings` (a String Catalog, EN +
  ES) instead of `.lproj`/`.strings` files (audit AF-21). Xcode's build system
  compiles it into `en.lproj`/`es.lproj`; the SwiftPM CLI (`swift build`/`swift
  test`) does not run that compilation step and ships the raw catalog verbatim —
  `LocalizationTests` reads whichever of the two `Bundle.module` provides.
