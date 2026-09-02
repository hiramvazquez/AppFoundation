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
/// Chrome defaults to `.native` (AF-12/AF-13): the navigation bar is never hidden unless a
/// screen opts into `chrome: .custom(...)`. Loading/error/empty/banner appearances come
/// from `Environment` (`LoadingViewStyle`, `ErrorViewStyle`, `EmptyViewStyle`,
/// `BannerViewStyle` — install with `.loadingViewStyle(_:)` etc.), so customizing them
/// never needs type erasure at the call site (AF-15).
///
/// Observation: the view-model initializer derives its bindings through `Bindable`, so
/// reads go straight to the `@Observable` view model during body evaluation and updates
/// are tracked automatically (A4 — no hand-rolled closures over an unobserved object).
public struct ScreenContainer<Content: View>: View {
    @Binding private var phase: ViewPhase
    @Binding private var activity: ActivityState
    @Binding private var alert: AlertState?
    @Binding private var banner: BannerState?

    private let chrome: ScreenChrome
    private let content: () -> Content
    private let backgroundColor: Color

    @Environment(\.loadingViewStyle) private var loadingStyle
    @Environment(\.errorViewStyle) private var errorStyle
    @Environment(\.emptyViewStyle) private var emptyStyle
    @Environment(\.bannerViewStyle) private var bannerStyle

    // MARK: - Initializers

    /// Creates a screen container bound to a `BaseViewModel`.
    public init(
        viewModel: BaseViewModel,
        chrome: ScreenChrome = .native,
        backgroundColor: Color = .platformBackground,
        @ViewBuilder content: @escaping () -> Content
    ) {
        let bindable = Bindable(viewModel)
        self._phase = bindable.phase
        self._activity = bindable.activity
        self._alert = bindable.alert
        self._banner = bindable.banner
        self.chrome = chrome
        self.content = content
        self.backgroundColor = backgroundColor
    }

    /// Creates a screen container using explicit bindings.
    public init(
        phase: Binding<ViewPhase>,
        activity: Binding<ActivityState> = .constant(.none),
        alert: Binding<AlertState?> = .constant(nil),
        banner: Binding<BannerState?> = .constant(nil),
        chrome: ScreenChrome = .native,
        backgroundColor: Color = .platformBackground,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._phase = phase
        self._activity = activity
        self._alert = alert
        self._banner = banner
        self.chrome = chrome
        self.content = content
        self.backgroundColor = backgroundColor
    }

    // MARK: - Body

    public var body: some View {
        chromeWrappedBody
            .animation(.default, value: phase)
            .animation(.default, value: activity)
            .animation(.default, value: banner)
            .onChange(of: banner) { _, newBanner in
                guard let newBanner else { return }
                // Accessibility: banners are transient — VoiceOver users hear them arrive.
                AccessibilityNotification.Announcement(newBanner.message).post()
            }
            // A15: alerts use the native presentation — there is no custom alert overlay
            // to opt into; a fully custom alert is a future `AlertViewStyle`, not a type-erased closure.
            .alert(
                alert?.title ?? "",
                isPresented: isAlertPresented,
                presenting: alert
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
    private func customChromeStack(navigation: NavigationBarConfiguration, placement: NavigationPlacement) -> some View {
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
            get: { alert != nil },
            set: { isPresented in
                if !isPresented { alert = nil }
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

            if banner != nil {
                bannerOverlayView
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var contentAreaView: some View {
        let hidden = ScreenPresentationLogic.hidesContent(phase)
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(hidden ? 0 : 1)
            .accessibilityHidden(hidden)
    }

    // MARK: - Phase and Activity Rendering

    @ViewBuilder
    private var primaryPhaseOverlay: some View {
        switch ScreenPresentationLogic.phaseOverlay(for: phase) {
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
        if let style = ScreenPresentationLogic.activityIndicator(for: activity) {
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
            if let bannerState = banner {
                bannerStyle.makeBody(configuration: BannerConfiguration(banner: bannerState) {
                    self.banner = nil
                })
            }
            Spacer()
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

public extension ScreenContainer {
    /// Convenience for a `.custom` chrome with just a title.
    ///
    /// Prefer `chrome: .native` with `.navigationTitle(_:)` for new screens.
    init(
        viewModel: BaseViewModel,
        title: LocalizedStringResource,
        style: NavigationBarStyle = .default,
        navigationPlacement: NavigationPlacement = .stack,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            viewModel: viewModel,
            chrome: .custom(.title(title, style: style), placement: navigationPlacement),
            content: content
        )
    }

    /// Convenience for a `.custom` chrome with a title and back button.
    ///
    /// Prefer `chrome: .native` with `.navigationTitle(_:)` — the system back button and
    /// swipe-back come for free, with no `PopGestureEnabler` workaround needed.
    init(
        viewModel: BaseViewModel,
        title: LocalizedStringResource,
        style: NavigationBarStyle = .default,
        navigationPlacement: NavigationPlacement = .stack,
        onBack: @escaping Action,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            viewModel: viewModel,
            chrome: .custom(.withBack(title: title, style: style, backAction: onBack), placement: navigationPlacement),
            content: content
        )
    }

    /// Convenience for a `.custom` chrome with a title and search bar.
    ///
    /// Prefer `chrome: .native` with `.searchable(text:)` — it integrates with the
    /// system's search keyboard, tokens, suggestions and scopes.
    init(
        viewModel: BaseViewModel,
        title: LocalizedStringResource,
        searchText: Binding<String>,
        searchPlaceholder: LocalizedStringResource? = nil,
        style: NavigationBarStyle = .solid,
        navigationPlacement: NavigationPlacement = .stack,
        onSearchSubmit: Action? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            viewModel: viewModel,
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

#endif
