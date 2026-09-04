#if canImport(SwiftUI)
import SwiftUI
import Accessibility

/// Defines where the custom navigation bar is rendered relative to screen content.
/// Only meaningful for `ScreenChrome.custom` — `.native` chrome has no notion of placement,
/// the system owns it.
public enum NavigationPlacement {
    /// Navigation bar participates in normal vertical layout (default).
    case stack
    /// Navigation bar is overlaid and remains fixed while content scrolls beneath.
    case overlay
}

/// How a `ScreenContainer` presents its navigation chrome (AF-12/AF-13).
///
/// `.native` is the default and the recommended choice for new screens: the system
/// navigation bar stays visible, and the screen drives it with the ordinary SwiftUI
/// modifiers (`navigationTitle`, `toolbar`, `searchable`) — large titles, scroll-edge
/// effects, and swipe-back all keep working for free, on every OS release.
///
/// `.custom` opts a screen OUT of the native bar in favor of `CustomNavigationBar`. Reach
/// for it only when the native bar genuinely can't do the job. Because hiding the native
/// bar also disables `UINavigationController`'s interactive pop gesture, `ScreenContainer`
/// installs `PopGestureEnabler` automatically whenever chrome is `.custom` — screens don't
/// need to think about it, but they should still verify swipe-back manually in a
/// simulator/device, since it can't be covered by a unit test.
public enum ScreenChrome {
    /// Use the caller's own `navigationTitle`/`toolbar`/`searchable` on the native bar.
    /// `ScreenContainer` does not touch navigation chrome at all in this mode.
    case native

    /// Hide the native bar and render `CustomNavigationBar` with the given configuration.
    case custom(NavigationBarConfiguration, placement: NavigationPlacement = .stack)
}

// MARK: - Presentation Logic

/// Pure presentation decisions for `ScreenContainer`, extracted so the activity system
/// is testable without snapshots: every phase/activity combination maps to an explicit,
/// renderable outcome — there is no invisible state (A2).
nonisolated enum ScreenPresentationLogic {
    /// What the primary phase renders above (or instead of) content.
    enum PhaseOverlay: Equatable {
        case none
        case loading(ActivityStyle)
        case error(ScreenError)
        case empty
    }

    /// Maps the primary phase to its overlay. Every `.loading` style produces a
    /// visible overlay — including `.inline`.
    static func phaseOverlay(for phase: ViewPhase) -> PhaseOverlay {
        switch phase {
        case .idle, .content:
            return .none
        case .loading(let style):
            return .loading(style)
        case .error(let error):
            return .error(error)
        case .empty:
            return .empty
        }
    }

    /// Whether the content area is hidden by the current primary phase.
    /// Only phases that fully replace content hide it.
    static func hidesContent(_ phase: ViewPhase) -> Bool {
        switch phase {
        case .error, .empty:
            return true
        case .loading(let style):
            return style == .fullScreen
        case .idle, .content:
            return false
        }
    }

    /// The activity indicator style to render for secondary activity, if any.
    static func activityIndicator(for activity: ActivityState) -> ActivityStyle? {
        if case .loading(let style) = activity { return style }
        return nil
    }

    /// Whether `chrome` hides the platform's native navigation bar (AF-12/AF-13/AF-14
    /// verification surface — pure logic, exercised without snapshots in
    /// `ScreenChromeTests`).
    static func hidesNativeBar(_ chrome: ScreenChrome) -> Bool {
        switch chrome {
        case .native: return false
        case .custom: return true
        }
    }
}

// MARK: - ScreenContainer

/// A screen shell with navigation chrome, screen-phase rendering, and feedback overlays.
///
/// `ScreenContainer` intentionally keeps a small public API while internally separating:
/// - base shell layout
/// - primary screen phase rendering (`phase`)
/// - transient activity overlays (`activity`)
/// - user feedback (`alert` via the native alert presentation, `banner` as an overlay)
///
/// `ScreenContainer` depends on `ScreenViewModel` (`ScreenState & ActionHandling`, AF-05),
/// never on the concrete `BaseViewModel` class: any `@Observable final class` that conforms
/// works, whether or not it inherits from `BaseViewModel`. The content closure receives an
/// `ActionSender<State.Action>` — never the view model itself — so a view cannot reach past
/// `handle(_:)` to call a method directly (`ScreenContainer(vm) { send in ... }` simply does
/// not compile unless `vm` conforms to `ActionHandling`; see `ActionHandlingTests` for the
/// documented negative-compile example).
///
/// Chrome defaults to `.native` (AF-12/AF-13): the navigation bar is never hidden unless a
/// screen opts into `chrome: .custom(...)`. Loading/error/empty/banner appearances come
/// from `Environment` (`LoadingViewStyle`, `ErrorViewStyle`, `EmptyViewStyle`,
/// `BannerViewStyle` — install with `.loadingViewStyle(_:)` etc.), so customizing them
/// never needs type erasure at the call site (AF-15).
///
/// Observation: `state` is read directly during `body` evaluation (no `@Bindable`/`Binding`
/// needed for reads — that's how `Observable` tracking works), so updates are tracked
/// automatically (A4 — no hand-rolled closures over an unobserved object).
public struct ScreenContainer<State: ScreenViewModel, Content: View>: View {
    private let state: State
    private let chrome: ScreenChrome
    private let content: (ActionSender<State.Action>) -> Content
    private let backgroundColor: Color

    @Environment(\.loadingViewStyle) private var loadingStyle
    @Environment(\.errorViewStyle) private var errorStyle
    @Environment(\.emptyViewStyle) private var emptyStyle
    @Environment(\.bannerViewStyle) private var bannerStyle

    // MARK: - Designated Initializer

    /// Creates a screen container bound to a `ScreenViewModel`: observable state
    /// (`ScreenState`) plus a single action entry point (`ActionHandling`). The content
    /// closure receives an `ActionSender<State.Action>` — send an action with
    /// `send(.load)`, never call a method on `state` directly.
    public init(
        _ state: State,
        chrome: ScreenChrome = .native,
        backgroundColor: Color = .platformBackground,
        @ViewBuilder content: @escaping (ActionSender<State.Action>) -> Content
    ) {
        self.state = state
        self.chrome = chrome
        self.content = content
        self.backgroundColor = backgroundColor
    }

    // MARK: - Body

    public var body: some View {
        chromeWrappedBody
            .animation(.default, value: state.phase)
            .animation(.default, value: state.activity)
            .animation(.default, value: state.banner)
            .onChange(of: state.banner) { _, newBanner in
                guard let newBanner else { return }
                // Accessibility: banners are transient — VoiceOver users hear them arrive.
                AccessibilityNotification.Announcement(newBanner.message).post()
            }
            // A15: alerts use the native presentation — there is no custom alert overlay
            // to opt into; a fully custom alert is a future `AlertViewStyle`, not a type-erased closure.
            .alert(
                state.alert?.title ?? "",
                isPresented: isAlertPresented,
                presenting: state.alert
            ) { alertState in
                alertButtons(for: alertState)
            } message: { alertState in
                Text(alertState.message)
            }
    }

    /// Installs chrome exactly once around the whole screen (content + every phase
    /// overlay), which is also what fixes AF-17: the previous implementation re-created
    /// `CustomNavigationBar` a second time for the error/empty overlay, duplicating the
    /// search `TextField` and its focus/keyboard state.
    @ViewBuilder
    private var chromeWrappedBody: some View {
        switch chrome {
        case .native:
            coreStack

        case .custom(let navigation, let placement):
            customChromeStack(navigation: navigation, placement: placement)
        }
    }

    @ViewBuilder
    private func customChromeStack(navigation: NavigationBarConfiguration, placement: NavigationPlacement) -> some View
    {
        Group {
            switch placement {
            case .stack:
                VStack(spacing: 0) {
                    CustomNavigationBar(configuration: navigation)
                    coreStack
                }
                .ignoresSafeArea(.container, edges: navigation.isVisible ? [] : .top)

            case .overlay:
                ZStack(alignment: .top) {
                    coreStack
                        .ignoresSafeArea(.container, edges: .top)
                    CustomNavigationBar(configuration: navigation)
                }
            }
        }
        #if os(iOS)
        // Hiding the native bar disables interactive pop — this workaround is the whole
        // reason `chrome: .custom` doesn't quietly break swipe-back (AF-12).
        .toolbar(.hidden, for: .navigationBar)
        .background(PopGestureEnabler().frame(width: 0, height: 0))
        #endif
    }

    private var isAlertPresented: Binding<Bool> {
        Binding(
            get: { state.alert != nil },
            set: { isPresented in
                if !isPresented { state.alert = nil }
            }
        )
    }

    @ViewBuilder
    private func alertButtons(for alertState: AlertState) -> some View {
        if let secondary = alertState.secondaryButton {
            Button(secondary.title, role: buttonRole(for: secondary.role)) {
                secondary.action()
            }
        }
        Button(alertState.primaryButton.title, role: buttonRole(for: alertState.primaryButton.role)) {
            alertState.primaryButton.action()
        }
    }

    private func buttonRole(for role: AlertState.Button.Role) -> ButtonRole? {
        switch role {
        case .default: return nil
        case .cancel: return .cancel
        case .destructive: return .destructive
        }
    }

    // MARK: - Core (content + phase/activity/banner overlays, chrome-agnostic)

    @ViewBuilder
    private var coreStack: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            contentAreaView

            primaryPhaseOverlay

            activityOverlay

            if state.banner != nil {
                bannerOverlayView
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var contentAreaView: some View {
        let hidden = ScreenPresentationLogic.hidesContent(state.phase)
        content(state.sender)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(hidden ? 0 : 1)
            .accessibilityHidden(hidden)
    }

    // MARK: - Phase and Activity Rendering

    @ViewBuilder
    private var primaryPhaseOverlay: some View {
        switch ScreenPresentationLogic.phaseOverlay(for: state.phase) {
        case .none:
            EmptyView()
        case .loading(let style):
            activityView(style: style)
                .transition(.opacity)
        case .error(let error):
            errorStyle.makeBody(configuration: ErrorConfiguration(error: error))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        case .empty:
            emptyStyle.makeBody(configuration: EmptyConfiguration())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var activityOverlay: some View {
        if let style = ScreenPresentationLogic.activityIndicator(for: state.activity) {
            activityView(style: style)
                .transition(.opacity)
        }
    }

    /// The ONE activity renderer, shared by the primary loading phase and secondary
    /// activity. Every style renders something (A2 is dead by construction).
    @ViewBuilder
    private func activityView(style: ActivityStyle) -> some View {
        let loadingBody = loadingStyle.makeBody(configuration: LoadingConfiguration(style: style))
        switch style {
        case .fullScreen:
            ZStack {
                backgroundColor.ignoresSafeArea()
                loadingBody
            }
        case .overlay:
            ZStack {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                loadingBody
            }
        case .inline:
            VStack {
                loadingBody
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Banner

    @ViewBuilder
    private var bannerOverlayView: some View {
        VStack(spacing: 0) {
            if let bannerState = state.banner {
                bannerStyle.makeBody(
                    configuration: BannerConfiguration(banner: bannerState) {
                        state.banner = nil
                    }
                )
            }
            Spacer()
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Convenience Initializers (custom chrome shorthands)

public extension ScreenContainer {
    /// Convenience for a `.custom` chrome with just a title.
    ///
    /// Prefer `chrome: .native` with `.navigationTitle(_:)` for new screens.
    init(
        _ state: State,
        title: LocalizedStringResource,
        style: NavigationBarStyle = .default,
        navigationPlacement: NavigationPlacement = .stack,
        @ViewBuilder content: @escaping (ActionSender<State.Action>) -> Content
    ) {
        self.init(
            state,
            chrome: .custom(.title(title, style: style), placement: navigationPlacement),
            content: content
        )
    }

    /// Convenience for a `.custom` chrome with a title and back button.
    ///
    /// Prefer `chrome: .native` with `.navigationTitle(_:)` — the system back button and
    /// swipe-back come for free, with no `PopGestureEnabler` workaround needed.
    init(
        _ state: State,
        title: LocalizedStringResource,
        style: NavigationBarStyle = .default,
        navigationPlacement: NavigationPlacement = .stack,
        onBack: @escaping Action,
        @ViewBuilder content: @escaping (ActionSender<State.Action>) -> Content
    ) {
        self.init(
            state,
            chrome: .custom(.withBack(title: title, style: style, backAction: onBack), placement: navigationPlacement),
            content: content
        )
    }

    /// Convenience for a `.custom` chrome with a title and search bar.
    ///
    /// Prefer `chrome: .native` with `.searchable(text:)` — it integrates with the
    /// system's search keyboard, tokens, suggestions and scopes.
    init(
        _ state: State,
        title: LocalizedStringResource,
        searchText: Binding<String>,
        searchPlaceholder: LocalizedStringResource? = nil,
        style: NavigationBarStyle = .solid,
        navigationPlacement: NavigationPlacement = .stack,
        onSearchSubmit: Action? = nil,
        @ViewBuilder content: @escaping (ActionSender<State.Action>) -> Content
    ) {
        self.init(
            state,
            chrome: .custom(
                .withSearch(
                    title: title,
                    searchText: searchText,
                    searchPlaceholder: searchPlaceholder,
                    style: style,
                    onSubmit: onSearchSubmit
                ),
                placement: navigationPlacement
            ),
            content: content
        )
    }
}

// MARK: - Bindings-only and read-only initializers (no `ActionHandling` required)

/// Backs `ScreenContainer(phase:activity:alert:banner:chrome:backgroundColor:content:)` —
/// the "no object" shorthand kept for previews, tests, and any screen that has no view
/// model at all. It has no actions of its own (`Action == Never`): the content closure for
/// that initializer is a plain `() -> Content`, exactly as before AF-05.
///
/// Not exposed as public API on its own — only reachable through `ScreenContainer`'s
/// bindings-only initializer, which is how `State` gets inferred to this type.
///
/// ## Why this observes correctly without `@Observable` doing any work (DC-AF-4)
///
/// `@Observable` is applied above for documentation and future-proofing, but it has no
/// effect here: the macro only instruments *stored* properties, and every property this
/// class exposes (`phase`, `activity`, `alert`, `banner`) is computed, forwarding straight
/// to a `Binding`'s `wrappedValue`. Re-rendering doesn't come from the Observation
/// framework at all — it comes from SwiftUI's own dependency tracking for `Binding`/`@State`,
/// which fires whenever `ScreenContainer.body` reads through one of these bindings during
/// evaluation, exactly as it would for any other `Binding` read in a view body. The
/// contract this type relies on is: never cache a binding's `wrappedValue` outside of
/// `body` evaluation, and never introduce a stored property that needs tracking — if one
/// is ever added, it must be observable through `@Observable`'s stored-property
/// instrumentation, not silently rely on this class's `Observable` conformance (inherited,
/// unconditionally, from `ScreenState`) to do it for free.
@MainActor
@Observable
public final class BindingBackedState: ScreenState, ActionHandling {
    // Explicit, nonisolated `deinit` on purpose. Under `defaultIsolation(MainActor)` a class
    // WITHOUT one gets a synthesized *isolated* deinit, which on OS versions older than the
    // toolchain's runtime goes through `swift_task_deinitOnExecutorMainActorBackDeploy`; two
    // of those nested (a ViewModel releasing its Coordinator) aborted with a libmalloc
    // double free on iOS 26.2 (AppStarter CI, Xcode 26.3). Nothing here needs the actor.
    deinit {}

    private let phaseBinding: Binding<ViewPhase>
    private let activityBinding: Binding<ActivityState>
    private let alertBinding: Binding<AlertState?>
    private let bannerBinding: Binding<BannerState?>

    init(
        phase: Binding<ViewPhase>,
        activity: Binding<ActivityState>,
        alert: Binding<AlertState?>,
        banner: Binding<BannerState?>
    ) {
        self.phaseBinding = phase
        self.activityBinding = activity
        self.alertBinding = alert
        self.bannerBinding = banner
    }

    public var phase: ViewPhase { phaseBinding.wrappedValue }
    public var activity: ActivityState { activityBinding.wrappedValue }
    public var alert: AlertState? {
        get { alertBinding.wrappedValue }
        set { alertBinding.wrappedValue = newValue }
    }
    public var banner: BannerState? {
        get { bannerBinding.wrappedValue }
        set { bannerBinding.wrappedValue = newValue }
    }

    public typealias Action = Never
    public func handle(_ action: Never) {}
}

/// Backs `ScreenContainer(observing:chrome:backgroundColor:content:)` — a **read-only**
/// screen: the shell renders `wrapped`'s phase/activity/alert/banner, but the content
/// closure gets no `ActionSender` because `wrapped` may not conform to `ActionHandling` at
/// all (it only needs `ScreenState`).
///
/// Not exposed as public API on its own — only reachable through `ScreenContainer`'s
/// `observing:` initializer and the `.screen(_:chrome:)` modifier, which is how `State`
/// gets inferred to this type.
///
/// ## Why this observes correctly without `@Observable` doing any work (DC-AF-4)
///
/// `@Observable` is applied above for documentation and future-proofing, but — like
/// `BindingBackedState` — it has no effect here: `phase`/`activity`/`alert`/`banner` are
/// computed properties that forward to `wrapped`, never stored ones the macro could
/// instrument. Observation tracking happens on `wrapped` itself: `wrapped` is guaranteed
/// `Observable` by the `ScreenState` protocol it conforms to (`BaseViewModel` gets this
/// from its own `@Observable`), so reading `wrapped.phase` during `ScreenContainer.body`
/// evaluation registers the access against `wrapped`'s registrar exactly as if the view
/// had read the wrapped view model directly — this class is a transparent pass-through
/// for tracking purposes, not a second source of truth. `ObservingScreenState` itself
/// never needs to be `@Observable`-instrumented because it stores no observable state of
/// its own (only a `let wrapped: Wrapped` reference, immutable after `init`).
@MainActor
@Observable
public final class ObservingScreenState<Wrapped: ScreenState>: ScreenState, ActionHandling {
    // Explicit, nonisolated `deinit` on purpose. Under `defaultIsolation(MainActor)` a class
    // WITHOUT one gets a synthesized *isolated* deinit, which on OS versions older than the
    // toolchain's runtime goes through `swift_task_deinitOnExecutorMainActorBackDeploy`; two
    // of those nested (a ViewModel releasing its Coordinator) aborted with a libmalloc
    // double free on iOS 26.2 (AppStarter CI, Xcode 26.3). Nothing here needs the actor.
    deinit {}

    let wrapped: Wrapped

    init(_ wrapped: Wrapped) {
        self.wrapped = wrapped
    }

    public var phase: ViewPhase { wrapped.phase }
    public var activity: ActivityState { wrapped.activity }
    public var alert: AlertState? {
        get { wrapped.alert }
        set { wrapped.alert = newValue }
    }
    public var banner: BannerState? {
        get { wrapped.banner }
        set { wrapped.banner = newValue }
    }

    public typealias Action = Never
    public func handle(_ action: Never) {}
}

public extension ScreenContainer where State == BindingBackedState {
    /// Creates a screen container using explicit bindings, without a view model. Kept for
    /// Xcode Previews and screens with no `ScreenViewModel` of their own — there is no
    /// `ActionSender` here (`content` is a plain `() -> Content`) because there is no
    /// `ActionHandling` to send to.
    init(
        phase: Binding<ViewPhase>,
        activity: Binding<ActivityState> = .constant(.none),
        alert: Binding<AlertState?> = .constant(nil),
        banner: Binding<BannerState?> = .constant(nil),
        chrome: ScreenChrome = .native,
        backgroundColor: Color = .platformBackground,
        @ViewBuilder content: @escaping () -> Content
    ) {
        let state = BindingBackedState(phase: phase, activity: activity, alert: alert, banner: banner)
        self.init(state, chrome: chrome, backgroundColor: backgroundColor) { _ in content() }
    }
}

public extension ScreenContainer {
    /// Creates a screen container for a **read-only** screen: `state` only needs to conform
    /// to `ScreenState`, not `ActionHandling` — there is no `ActionSender` in `content`
    /// because there is nothing to send to.
    init<Wrapped: ScreenState>(
        observing state: Wrapped,
        chrome: ScreenChrome = .native,
        backgroundColor: Color = .platformBackground,
        @ViewBuilder content: @escaping () -> Content
    ) where State == ObservingScreenState<Wrapped> {
        self.init(ObservingScreenState(state), chrome: chrome, backgroundColor: backgroundColor) { _ in content() }
    }
}

#endif
