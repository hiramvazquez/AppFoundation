# AppFoundation

AppFoundation is a single Swift Package for new SwiftUI apps. It gives every project the same baseline for screen state, secondary activity handling, navigation, dependency injection, shell UI, and a few reusable utilities.

Requires **Swift 6.2** (tools), **iOS 17 / macOS 14**. The package builds with
`defaultIsolation(MainActor)` (Approachable Concurrency) and warnings as errors.

## What it includes

- **Architecture**
  - `BaseViewModel` (`@Observable`) + `LoadableViewModel` (`performLoad`/`performActivity`/`load`/`activity`)
  - `ScreenState` / `ActionHandling` / `ActionSender` — the screen ↔ shell contract
    (`ScreenContainer` depends on these protocols, not on `BaseViewModel`)
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
  - `ScreenContainer` (native navigation chrome by default — `ScreenChrome.custom` is opt-in;
    depends on `ScreenState`/`ActionHandling`, never on the concrete `BaseViewModel` class)
  - `.screen(_:chrome:)` — `ScreenContainer`'s chrome/phase rendering for a read-only
    `ScreenState`, as a `View` modifier
  - `LoadingViewStyle` / `ErrorViewStyle` / `EmptyViewStyle` / `BannerViewStyle` (`Environment`-propagated, no `AnyView`)
  - `CustomNavigationBar` / `NavigationBarItem` (stable identity + semantic roles; opt-in via `ScreenChrome.custom`)
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

`ScreenContainer` needs the view model to conform to `ActionHandling` (AF-05, see «Acciones:
un solo punto de entrada» below): an `Action` enum names every gesture the screen
recognizes, `handle(_:)` is the only method a view calls, and everything else can be
`private`.

```swift
import AppFoundation

struct Profile {
    let name: String
}

final class ProfileViewModel: BaseViewModel, ActionHandling {
    private(set) var profile: Profile?

    private let repository: ProfileRepository
    private let router: any Router<AppRoute>

    enum Action: Sendable {
        case onAppear
        case refresh
        case openDetails
    }

    init(
        repository: ProfileRepository,
        router: any Router<AppRoute>
    ) {
        self.repository = repository
        self.router = router
        super.init()
    }

    func handle(_ action: Action) {
        switch action {
        case .onAppear: onAppear()
        case .refresh: refresh()
        case .openDetails: openDetails()
        }
    }

    private func onAppear() {
        performLoad(successTransition: .preserveCurrentPhase) { vm in
            let profile = try await vm.repository.fetchProfile()
            vm.profile = profile
            vm.setContent()
        }
    }

    private func refresh() {
        performActivity(style: .overlay) { vm in
            let profile = try await vm.repository.fetchProfile()
            vm.profile = profile
            vm.showBanner(.success("Profile updated"))
        }
    }

    private func openDetails() {
        router.push(.profileDetails(id: "42"))
    }
}
```

`BaseViewModel` is `@Observable`: stored properties in subclasses are tracked
automatically — no `@Published`, no `ObservableObject`.

### 6. Render with `ScreenContainer`

`ScreenContainer(chrome:)` defaults to `.native`: the system navigation bar stays visible,
and the screen drives it the ordinary SwiftUI way — `navigationTitle`, `toolbar`,
`searchable`. That means large titles, scroll-edge effects, and (importantly)
swipe-back all keep working for free, on every OS release. The content closure receives an
`ActionSender<ProfileViewModel.Action>` — call it `send(.refresh)` — never the view model
itself:

```swift
struct ProfileView: View {
    let viewModel: ProfileViewModel

    var body: some View {
        ScreenContainer(viewModel) { send in
            VStack(spacing: 20) {
                if let profile = viewModel.profile {
                    Text(profile.name)
                        .font(.title)
                }

                Button("Refresh") {
                    send(.refresh)
                }

                Button("Open details") {
                    send(.openDetails)
                }
            }
            .padding()
            .onAppear {
                send(.onAppear)
            }
        }
        .navigationTitle("Profile")
    }
}
```

`viewModel.profile` above still reads the view model directly — `ScreenState`
(`phase`/`activity`/`alert`/`banner`) and `Profile` are both fine to read from `viewModel`
for rendering; only *acting* on the screen goes through `send`.

Alerts present through the native `.alert` by default; banners auto-dismiss after their
duration and are announced to VoiceOver.

Loading/error/empty/banner appearances are pluggable through `Environment`, the same
pattern SwiftUI uses for `ButtonStyle`/`ProgressViewStyle` — no `AnyView` at the call site:

```swift
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

ScreenContainer(viewModel) { send in ContentView() }
    .errorViewStyle(BrandErrorStyle())
```

#### Opt-in custom navigation bar

Reach for `chrome: .custom(...)` only when the native bar genuinely can't do the job (e.g.
a header with an avatar and a greeting). Hiding the native bar also disables
`UINavigationController`'s interactive pop gesture — `ScreenContainer` installs the
`PopGestureEnabler` workaround automatically whenever chrome is `.custom`, but you should
still verify swipe-back manually on a simulator/device, since that can't be covered by a
unit test:

```swift
ScreenContainer(
    viewModel,
    chrome: .custom(.withBack(title: "Profile") {
        // Usually delegated back to router/coordinator owner
    })
) { send in
    ProfileContent()
}
```

## Acciones: un solo punto de entrada

`ActionHandling` (AF-05) is the contract behind every `ScreenContainer(_:chrome:content:)`
call above: a view model names its `Action`s and implements a single `handle(_:)` — the
ONLY method a view (or a test) calls. Everything else the view model does can be `private`.

```swift
@Observable
final class ProfileViewModel: BaseViewModel, ActionHandling {
    enum Action: Sendable {
        case load
        case refresh
    }

    private(set) var profile: Profile?
    private let repository: ProfileRepository

    init(repository: ProfileRepository) {
        self.repository = repository
        super.init()
    }

    func handle(_ action: Action) {
        switch action {
        case .load: load()
        case .refresh: refresh()
        }
    }

    private func load() {
        performLoad { vm in vm.profile = try await vm.repository.fetchProfile() }
    }

    private func refresh() {
        performActivity(style: .overlay) { vm in
            vm.profile = try await vm.repository.fetchProfile()
        }
    }
}
```

The view never sees `load()`/`refresh()` — `ScreenContainer`'s content closure hands it an
`ActionSender<ProfileViewModel.Action>` instead, built from `handle(_:)` behind a `weak`
reference (`ActionHandling.sender`), so holding on to a `send` closure never keeps the view
model alive:

```swift
struct ProfileView: View {
    let viewModel: ProfileViewModel

    var body: some View {
        ScreenContainer(viewModel) { send in
            VStack {
                Text(viewModel.profile?.name ?? "—")
                Button("Refresh") { send(.refresh) }
            }
            .onAppear { send(.load) }
        }
    }
}
```

Tests call `handle(_:)` directly — the same call the view makes — and assert on observable
state, without `@testable import` reaching past a `private` method:

```swift
@Test func loadReachesContent() async throws {
    let viewModel = ProfileViewModel(repository: LiveProfileRepository())

    viewModel.handle(.load)
    try await waitUntil { viewModel.phase == .content }

    #expect(viewModel.profile != nil)
}
```

A subview many levels deep that needs to send actions without the intermediate views
prop-drilling `send` can install its own concretely-typed `@Entry` from inside the content
closure — the same `Environment` pattern the DI section above uses for `analytics` — because
`send` is already in scope right there:

```swift
extension EnvironmentValues {
    @Entry var profileActions: ActionSender<ProfileViewModel.Action>?
}

ScreenContainer(viewModel) { send in
    ProfileContent()
        .environment(\.profileActions, send)
}
```

AppFoundation doesn't ship a generic, one-size-fits-all `EnvironmentKey` for
`ActionSender<Action>` — a single `EnvironmentKey` can't carry a different `Action` type per
screen without either a metatype-keyed subscript (fragile to spell correctly at call sites)
or one `@Entry` per concrete `Action` type (which is exactly the snippet above, and no more
code than declaring the key once per screen that actually needs it).

## Pantalla y cáscara: el contrato `ScreenState`

Before AF-05, `ScreenContainer` took a concrete `BaseViewModel` — so any screen that wanted
the shell had to inherit from it, even a screen that only used four of its properties.
`ScreenContainer` depends on `ScreenState` instead:

```swift
@MainActor
public protocol ScreenState: AnyObject, Observable {
    var phase: ViewPhase { get }
    var activity: ActivityState { get }
    var alert: AlertState? { get set }
    var banner: BannerState? { get set }
}
```

`BaseViewModel` conforms (`extension BaseViewModel: ScreenState {}`), but any other
`@Observable final class` can conform too, without inheriting from `BaseViewModel` at all —
`ScreenContainer(_ state: State, ...)` only requires `State: ScreenState & ActionHandling`
(the `ScreenViewModel` typealias).

Two things worth explaining:

- **Why a class taken by value, not a `Binding`.** `ScreenState: AnyObject, Observable` —
  `ScreenContainer` reads `state.phase` directly in `body`; that's how `Observable` tracking
  works (no `@Bindable`/`Binding` needed for reads). It only needs to *write* `alert`/
  `banner` (to dismiss them), which a reference type's stored property supports without any
  `Binding` machinery.
- **Why a protocol, not a class.** Swift has no abstract methods, so `BaseViewModel` alone
  cannot force a subclass to implement anything — a protocol with an associated type
  (`ActionHandling.Action`) can, at compile time. `ScreenContainer(vm) { send in ... }`
  simply does not compile unless `vm` conforms to `ActionHandling`.

A screen with nothing to `handle(_:)` — pure navigation, pure read-only state — doesn't need
`ActionHandling` at all. `ScreenContainer(observing:)` and the `.screen(_:chrome:)` modifier
take a plain `ScreenState`, with no `ActionSender` in `content` because there is nothing to
send to:

```swift
struct DashboardView: View {
    let viewModel: DashboardViewModel   // a BaseViewModel with no ActionHandling

    var body: some View {
        DashboardContent(viewModel: viewModel)
            .screen(viewModel)
    }
}
```

`PhaseView` has the same read-only shape: `PhaseView(observing: viewModel) { ... }` reads
`phase` directly, without a `Binding`.

### Why `BindingBackedState`/`ObservingScreenState` observe correctly without `@Observable` doing any work

Both of `ScreenContainer`'s no-view-model backing types — `BindingBackedState` (the
bindings-only initializer) and `ObservingScreenState` (the read-only `observing:`
initializer) — carry `@Observable` for documentation, but the macro has nothing to
instrument on either: every property they expose (`phase`, `activity`, `alert`, `banner`)
is computed, forwarding straight through to a `Binding` or to a wrapped `ScreenState`,
never a stored property the macro could wrap. Reading them during `ScreenContainer.body`'s
evaluation still triggers the right invalidation:

- `BindingBackedState` forwards to a `Binding` — reactivity comes from SwiftUI's own
  `Binding`/`@State` dependency tracking, the same mechanism that updates a view for any
  other `Binding` read in its `body`, entirely separate from the `Observation` framework.
- `ObservingScreenState<Wrapped>` forwards to `wrapped: Wrapped`, which the `ScreenState`
  protocol already guarantees is `Observable` (`BaseViewModel` gets that from its own
  `@Observable`) — reading `wrapped.phase` registers the access against `wrapped`'s own
  registrar, exactly as if the view had read the wrapped view model directly.

Both types' doc comments carry the full rationale (`ScreenContainer.swift`).

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

When the call you're testing goes through `handle(_:)` instead — the normal case for a
`ScreenContainer` content closure, or any test written against `ActionHandling`'s single
entry point — there's no returned `Task` to await, since `handle(_:)` is `Void` by
contract (AF-05). `BaseViewModel` exposes the `Task` it's currently running instead, as
`inFlightLoad`/`inFlightActivity: Task<Void, Never>?` (read-only, `nil` once the load/
activity finishes):

```swift
viewModel.handle(.load)
await viewModel.inFlightLoad?.value
#expect(viewModel.phase == .content)
```

Use `inFlightLoad` for anything that goes through `performLoad`/`load(_:)`, and
`inFlightActivity` for `performActivity`/`activity(_:)` — including a retry (`retry` calls
`performLoad` again internally, so `inFlightLoad` picks up the new `Task`). Never poll
`phase`/`hasError` in a loop to detect completion — sleeping in a spin loop to wait out
async work is exactly what these properties exist to make unnecessary.

`clock` and `cancellationRecognizer` follow `errorPresenter`'s precedence: an instance
override (through `init`) beats `BaseViewModel.clock`/`BaseViewModel.cancellationRecognizer`
(the `static var`s, meant for app-wide configuration at startup). Tests inject their own
`Clock`/`CancellationRecognizing` conformance per instance instead of mutating the static —
a `static var` mutated by one test is visible to every other test running in parallel,
which is exactly the kind of flake `inFlightLoad`/`inFlightActivity` are also trying to
eliminate:

```swift
let viewModel = BaseViewModel(clock: someManualClockConformance)
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

- `ScreenContainer` is the public shell type; it depends on `ScreenViewModel`
  (`ScreenState & ActionHandling`, AF-05), never on the concrete `BaseViewModel` class.
- `performLoad`/`performActivity` (unstructured, `Task`-returning) and `load`/`activity`
  (structured, run inline in the caller's own `Task`) come from `LoadableViewModel`;
  `work` always takes the view model as a parameter, never by capture.
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
- If a stale `.build` from before this package moved to `.xcstrings` is still
  around, `Bundle.module` can find leftover compiled `en.lproj`/`es.lproj`
  directories from that earlier build sitting next to the catalog's own
  resource bundle — a mismatch that only shows up as an unexpected string
  lookup, never a compile error. A clean build (`rm -rf .build` or Xcode's
  "Clean Build Folder") resolves it; it is not a bug in the catalog itself.

## License

MIT — see [LICENSE](../LICENSE) at the repository root.
