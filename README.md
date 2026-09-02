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
  - `Debouncer` / `Throttler` (injectable `Clock`)
  - `WrappedError` (`AppErrorConvertible`)
  - `AppEnvironment`

All user-visible default strings ship localized (EN + ES); visible-copy parameters
accept `LocalizedStringResource`, so string literals localize through your app's catalog.

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

`Container` is the composition root: the one place that knows concrete types. Register
once, at startup, on the main actor (the container is `@MainActor`, like everything that
uses it).

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

@main
struct MyApp: App {
    init() {
        Container.shared.register(modules: [ProfileModule()])
    }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}
```

`register(_:lifecycle:factory:)` defaults to `.singleton` (one instance per container,
built lazily); `.transient` builds one per resolution. An object you already hold goes in
with `register(instance:as:)`.

`Container.shared` is a `static let` and can never be swapped. Tests and previews use
child containers, which shadow the parent without mutating it:

```swift
let container = Container(parent: .shared)
container.register(instance: MockProfileRepository(), as: ProfileRepository.self)
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

## Dependency injection

`Container` is `@MainActor`. There is no mutex and no unchecked `Sendable` conformance:
the compiler guarantees that factories for main-actor types run on the main actor, and `nonisolated`
code never resolves — it receives its dependencies through `init`. Calling `resolve()`
from a `nonisolated` context is a compile error, not a documented convention.

### Composition root

Registration happens once, at startup, in `Container.shared` (see §1). Feature modules
register abstractions and their live implementations; nothing else in the app calls
`register`.

### One child container per flow

A checkout, a session, a wizard: dependencies that must outlive a screen but not the app
are `.singleton` in a **child container owned by the flow**. No named scope to create or
destroy — the flow ends when its container is released.

```swift
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
```

A factory registered in a parent resolves from the parent, even when resolved through a
child: overriding `ProfileRepository` in a test child never rebuilds a `Container.shared`
singleton with the mock.

### Which mechanism, when

| You are building | Use | Why |
|---|---|---|
| View models, services, repositories | Constructor injection (`init`) | The dependency is in the signature; the compiler checks it; tests pass a double. |
| Views | `Environment` (`@Entry` on `EnvironmentValues`) | Scoped to the view tree, overridable per subtree, understood by previews; a `struct View` stays a value. |
| Leaf classes where threading a dependency costs more than it clarifies (an analytics adapter) | `@Inject` | Last resort: hides the dependency and traps at runtime if it is not registered. |

`@Inject` is a class: inside a `struct View` it keeps its cached value across copies
without being a `DynamicProperty`, so SwiftUI cannot see it. Views read their
dependencies from the environment and the composition root injects them at the top:

```swift
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
```

`@Inject`, kept for leaf classes only:

```swift
final class AnalyticsAdapter {
    @Inject private var analytics: AnalyticsService

    func track(_ event: String) {
        analytics.log(event)
    }
}
```

`@Inject` is `@MainActor` and requires the type to be registered (it traps otherwise —
absence is not modelled; use `Container.tryResolve` when it is).

### Cycles

A factory that resolves the type it is building — A → B → A — traps with a message
naming every type in the cycle. Break it by passing one side through its initializer.

## Notes

- `ScreenContainer` is the public shell type.
- `performLoad(...)` / `performActivity(...)` are the single async entry points
  (the legacy `load(...)` wrapper is gone).
- `Debouncer` and `Throttler` accept an injectable `Clock` for deterministic tests;
  the convenience initializers default to `ContinuousClock`.
