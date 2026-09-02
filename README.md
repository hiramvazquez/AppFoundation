# AppFoundation

AppFoundation is a single Swift Package for new SwiftUI apps. It gives every project the same baseline for screen state, secondary activity handling, navigation, dependency injection, shell UI, and a few reusable utilities.

Requires **Swift 6.2** (tools), **iOS 17 / macOS 14**. The package builds with
`defaultIsolation(MainActor)` (Approachable Concurrency) and warnings as errors.

## What it includes

- **Architecture**
  - `BaseViewModel` (`@Observable`) + `LoadableViewModel` (`performLoad`/`performActivity`/`load`/`activity`)
  - `ErrorPresenting` / `DefaultErrorPresenter` (single place to map errors to copy)
  - `CancellationRecognizing` / `DefaultCancellationRecognizer`
  - `ViewPhase` / `ActivityStyle` / `ActivityState`
  - `AlertState`
  - `BannerState` (real auto-dismiss, injectable `Clock`)
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
- `work` never captures the view model: `performLoad { vm in ... }`/`performActivity { vm in ... }`
  hand the view model in as a parameter instead of relying on closure capture. That's
  what makes `deinit` actually cancel in-flight work instead of leaking forever.

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

## Errors: `ErrorPresenting` is the single place that maps errors to copy

`performLoad`/`performActivity` never show `error.localizedDescription` for a foreign
`Error`. For a plain Swift type that isn't `LocalizedError` (most domain enums,
including a typical `APIError`), that string reads like *"The operation couldn't be
completed. (Module.Type error 9.)"* — never on screen. Instead, every error goes
through an `ErrorPresenting`:

```swift
public protocol ErrorPresenting: Sendable {
    func screenError(for error: any Error, fallbackTitle: String, retry: Action?) -> ScreenError
}
```

`BaseViewModel.errorPresenter` (a `static var`, defaulting to `DefaultErrorPresenter()`)
is the one place an app maps errors to user-facing copy — set it once at startup, and
every screen in the app benefits without touching each view model:

```swift
struct AppErrorPresenter: ErrorPresenting {
    func screenError(for error: any Error, fallbackTitle: String, retry: Action?) -> ScreenError {
        // An example that classifies a network error by category, without this
        // package depending on any particular networking library:
        if let network = error as? NetworkError {
            switch network.category {
            case .offline:
                return ScreenError(title: "No connection", message: "Check your network and try again.", retry: retry)
            case .unauthorized:
                return ScreenError(title: "Session expired", message: "Please sign in again.")
            default:
                break
            }
        }
        return DefaultErrorPresenter().screenError(for: error, fallbackTitle: fallbackTitle, retry: retry)
    }
}

// At app startup:
BaseViewModel.errorPresenter = AppErrorPresenter()
```

`DefaultErrorPresenter` (used when nothing is configured) resolves in this order:

1. `AppErrorConvertible` — the error already knows how to present itself.
2. `LocalizedError` with a non-`nil` `errorDescription` — the fallback title (the
   `errorTitle` passed to `performLoad`, or `L10n.error`) plus that description.
3. Anything else — the fallback title plus a generic, localized message. The technical
   detail is logged (`AppFoundationLogger.errors`, `.private`), never shown.

A single view model can override the presenter for itself through
`BaseViewModel(errorPresenter:)` — useful for a screen with unusual error copy, without
touching the app-wide default. Precedence is instance override, then
`BaseViewModel.errorPresenter`, then `DefaultErrorPresenter()`.

### `AppErrorConvertible`: the easiest way to plug in a domain error

Conform your domain errors to `AppErrorConvertible` and they surface *their own* title
and message without an `ErrorPresenting` at all — this is what `WrappedError` does:

```swift
enum ProfileError: Error, AppErrorConvertible {
    case notFound

    var screenError: ScreenError {
        ScreenError(title: "Profile unavailable", message: "Try again later.")
    }
}
```

### Cancellation

A cancelled load is never surfaced as a screen error. Beyond typed `CancellationError`,
`BaseViewModel.cancellationRecognizer` (default: `CancellationError` and
`URLError(.cancelled)`) is consulted too — extend it if your app's error type wraps or
maps cancellation to something else:

```swift
struct AppCancellationRecognizer: CancellationRecognizing {
    func isCancellation(_ error: any Error) -> Bool {
        DefaultCancellationRecognizer().isCancellation(error) || (error as? NetworkError)?.isCancellation == true
    }
}
BaseViewModel.cancellationRecognizer = AppCancellationRecognizer()
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

`performLoad`/`performActivity`/`load`/`activity` come from `LoadableViewModel`, which
`BaseViewModel` conforms to — every subclass gets them automatically. `work` receives
the view model as a parameter (`{ vm in ... }`) instead of capturing it. This isn't a
style preference: a closure that captures `self` instead of using `vm` can recreate the
`self → phase → retry → work → self` cycle this API exists to prevent. Always go through
`vm`, never through an outer `self` the closure happens to have access to.

### For initial load

```swift
performLoad { vm in
    let data = try await vm.service.fetch()
    vm.items = data
}
```

### When the work decides the next phase itself

```swift
performLoad(successTransition: .preserveCurrentPhase) { vm in
    let items = try await vm.service.fetch()
    vm.items = items
    if items.isEmpty {
        vm.setEmpty()
    } else {
        vm.setContent()
    }
}
```

### For secondary work

```swift
performActivity(style: .inline) { vm in
    try await vm.service.sync()
}
```

### Structured variant: cancellation follows the view, not `deinit`

`load`/`activity` run `work` inline in the caller's own `Task` instead of an
unstructured one owned by the view model — use them from `.task`, where SwiftUI already
cancels on disappearance:

```swift
.task {
    await viewModel.load { vm in
        vm.items = try await vm.service.fetch()
    }
}
```

Reach for `performLoad`/`performActivity` (the `Task`-returning pair) for actions that
should outlive a single tap, like a button-triggered submit.

### Deterministic tests

Both helpers return their `Task` — await it instead of sleeping:

```swift
await viewModel.performLoad { vm in try await vm.repository.fetch() }.value
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
- `performLoad`/`performActivity` (unstructured, `Task`-returning) and `load`/`activity`
  (structured, run inline in the caller's own `Task`) come from `LoadableViewModel`;
  `work` always takes the view model as a parameter, never by capture.
- `Debouncer` and `Throttler` accept an injectable `Clock` for deterministic tests;
  the convenience initializers default to `ContinuousClock`.
