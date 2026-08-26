#if canImport(SwiftUI)
import SwiftUI
import Accessibility

/// Defines where the custom navigation bar is rendered relative to screen content.
public enum NavigationPlacement {
    /// Navigation bar participates in normal vertical layout (default).
    case stack
    /// Navigation bar is overlaid and remains fixed while content scrolls beneath.
    case overlay
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
/// Observation: the view-model initializer derives its bindings through `Bindable`, so
/// reads go straight to the `@Observable` view model during body evaluation and updates
/// are tracked automatically (A4 — no hand-rolled closures over an unobserved object).
public struct ScreenContainer<Content: View>: View {
    @Binding private var phase: ViewPhase
    @Binding private var activity: ActivityState
    @Binding private var alert: AlertState?
    @Binding private var banner: BannerState?

    private let navigation: NavigationBarConfiguration
    private let navigationPlacement: NavigationPlacement
    private let content: () -> Content
    private let backgroundColor: Color

    private var loadingViewBuilder: (() -> AnyView)?
    private var errorViewBuilder: ((ScreenError) -> AnyView)?
    private var emptyViewBuilder: (() -> AnyView)?
    private var alertViewBuilder: ((AlertState) -> AnyView)?
    private var bannerViewBuilder: ((BannerState) -> AnyView)?

    // MARK: - Initializers

    /// Creates a screen container bound to a `BaseViewModel`.
    public init(
        viewModel: BaseViewModel,
        navigation: NavigationBarConfiguration = .hidden,
        navigationPlacement: NavigationPlacement = .stack,
        backgroundColor: Color = .platformBackground,
        @ViewBuilder content: @escaping () -> Content
    ) {
        let bindable = Bindable(viewModel)
        self._phase = bindable.phase
        self._activity = bindable.activity
        self._alert = bindable.alert
        self._banner = bindable.banner
        self.navigation = navigation
        self.navigationPlacement = navigationPlacement
        self.content = content
        self.backgroundColor = backgroundColor
    }

    /// Creates a screen container using explicit bindings.
    public init(
        phase: Binding<ViewPhase>,
        activity: Binding<ActivityState> = .constant(.none),
        alert: Binding<AlertState?> = .constant(nil),
        banner: Binding<BannerState?> = .constant(nil),
        navigation: NavigationBarConfiguration = .hidden,
        navigationPlacement: NavigationPlacement = .stack,
        backgroundColor: Color = .platformBackground,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._phase = phase
        self._activity = activity
        self._alert = alert
        self._banner = banner
        self.navigation = navigation
        self.navigationPlacement = navigationPlacement
        self.content = content
        self.backgroundColor = backgroundColor
    }

    // MARK: - Body

    public var body: some View {
        let core = ZStack {
            backgroundColor.ignoresSafeArea()

            mainContentView

            primaryPhaseOverlay

            activityOverlay

            if banner != nil {
                bannerOverlayView
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Transiciones dirigidas por transacción (A15): los cambios de estado animan sin
        // que cada mutación tenga que envolverse en withAnimation en el ViewModel.
        .animation(.default, value: phase)
        .animation(.default, value: activity)
        .animation(.default, value: banner)
        .onChange(of: banner) { _, newBanner in
            guard let newBanner else { return }
            // Accessibility: banners are transient — VoiceOver users hear them arrive.
            AccessibilityNotification.Announcement(newBanner.message).post()
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif

        Group {
            if alertViewBuilder != nil {
                core.overlay {
                    if alert != nil {
                        alertOverlayView
                            .transition(.opacity)
                    }
                }
                .animation(.default, value: alert)
            } else {
                // A15: alerts use the native presentation by default.
                core.alert(
                    alert?.title ?? "",
                    isPresented: isAlertPresented,
                    presenting: alert
                ) { alertState in
                    alertButtons(for: alertState)
                } message: { alertState in
                    Text(alertState.message)
                }
            }
        }
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

    // MARK: - Main Content

    @ViewBuilder
    private var mainContentView: some View {
        switch navigationPlacement {
        case .stack:
            VStack(spacing: 0) {
                if navigation.isVisible {
                    Color.clear
                        .frame(height: 0)
                        .background(navigationBarBackground)
                }

                CustomNavigationBar(configuration: navigation)
                contentAreaView
            }
            .edgesIgnoringSafeArea(navigation.isVisible ? [] : .top)

        case .overlay:
            ZStack(alignment: .top) {
                contentAreaView
                    .edgesIgnoringSafeArea(.top)

                if navigation.isVisible {
                    CustomNavigationBar(configuration: navigation)
                }
            }
        }
    }

    @ViewBuilder
    private var contentAreaView: some View {
        let hidden = ScreenPresentationLogic.hidesContent(phase)
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(hidden ? 0 : 1)
            .accessibilityHidden(hidden)
    }

    @ViewBuilder
    private var navigationBarBackground: some View {
        switch navigation.style.background {
        case .solid(let color):
            color
        case .blur(let material):
            Rectangle().fill(material)
        case .gradient(let gradient):
            gradient
        }
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
            errorOverlayView(error: error)
                .transition(.opacity)
        case .empty:
            emptyOverlayView
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
        switch style {
        case .fullScreen:
            ZStack {
                backgroundColor.ignoresSafeArea()
                builtLoadingView
            }
        case .overlay:
            ZStack {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                builtLoadingView
            }
        case .inline:
            VStack {
                builtInlineActivityView
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var builtLoadingView: some View {
        if let builder = loadingViewBuilder {
            builder()
        } else {
            DefaultLoadingView()
        }
    }

    @ViewBuilder
    private var builtInlineActivityView: some View {
        if let builder = loadingViewBuilder {
            builder()
        } else {
            DefaultInlineActivityView()
        }
    }

    // MARK: - Overlay Views

    @ViewBuilder
    private func errorOverlayView(error: ScreenError) -> some View {
        stateOverlayContainer {
            if let builder = errorViewBuilder {
                builder(error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DefaultErrorView(error: error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var emptyOverlayView: some View {
        stateOverlayContainer {
            if let builder = emptyViewBuilder {
                builder()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DefaultEmptyView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func stateOverlayContainer<Overlay: View>(@ViewBuilder overlay: () -> Overlay) -> some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            switch navigationPlacement {
            case .stack:
                VStack(spacing: 0) {
                    if navigation.isVisible {
                        CustomNavigationBar(configuration: navigation)
                    }
                    overlay()
                }
            case .overlay:
                ZStack(alignment: .top) {
                    overlay()
                    if navigation.isVisible {
                        CustomNavigationBar(configuration: navigation)
                    }
                }
            }
        }
    }

    /// Custom alert overlay — only used when `alertView(builder:)` was provided;
    /// the default path presents alerts natively.
    @ViewBuilder
    private var alertOverlayView: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { }

            if let alertState = alert, let builder = alertViewBuilder {
                builder(alertState)
            }
        }
    }

    @ViewBuilder
    private var bannerOverlayView: some View {
        VStack(spacing: 0) {
            if let bannerState = banner {
                if let builder = bannerViewBuilder {
                    builder(bannerState)
                } else {
                    DefaultBannerView(banner: bannerState) {
                        self.banner = nil
                    }
                }
            }
            Spacer()
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Custom View Builders

    public func loadingView<V: View>(@ViewBuilder builder: @escaping () -> V) -> Self {
        var copy = self
        copy.loadingViewBuilder = { AnyView(builder()) }
        return copy
    }

    public func errorView<V: View>(@ViewBuilder builder: @escaping (ScreenError) -> V) -> Self {
        var copy = self
        copy.errorViewBuilder = { AnyView(builder($0)) }
        return copy
    }

    public func emptyView<V: View>(@ViewBuilder builder: @escaping () -> V) -> Self {
        var copy = self
        copy.emptyViewBuilder = { AnyView(builder()) }
        return copy
    }

    /// Replaces the native alert presentation with a fully custom overlay.
    public func alertView<V: View>(@ViewBuilder builder: @escaping (AlertState) -> V) -> Self {
        var copy = self
        copy.alertViewBuilder = { AnyView(builder($0)) }
        return copy
    }

    public func bannerView<V: View>(@ViewBuilder builder: @escaping (BannerState) -> V) -> Self {
        var copy = self
        copy.bannerViewBuilder = { AnyView(builder($0)) }
        return copy
    }
}

public extension ScreenContainer {
    init(
        viewModel: BaseViewModel,
        title: String,
        style: NavigationBarStyle = .default,
        navigationPlacement: NavigationPlacement = .stack,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            viewModel: viewModel,
            navigation: .title(title, style: style),
            navigationPlacement: navigationPlacement,
            content: content
        )
    }

    init(
        viewModel: BaseViewModel,
        title: String,
        style: NavigationBarStyle = .default,
        navigationPlacement: NavigationPlacement = .stack,
        onBack: @escaping Action,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            viewModel: viewModel,
            navigation: .withBack(title: title, style: style, backAction: onBack),
            navigationPlacement: navigationPlacement,
            content: content
        )
    }

    init(
        viewModel: BaseViewModel,
        title: String,
        searchText: Binding<String>,
        searchPlaceholder: String = "Search",
        style: NavigationBarStyle = .solid,
        navigationPlacement: NavigationPlacement = .stack,
        onSearchSubmit: Action? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            viewModel: viewModel,
            navigation: .withSearch(
                title: title,
                searchText: searchText,
                searchPlaceholder: searchPlaceholder,
                style: style,
                onSubmit: onSearchSubmit
            ),
            navigationPlacement: navigationPlacement,
            content: content
        )
    }
}

// MARK: - Default Views

struct DefaultLoadingView: View {
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.large)
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct DefaultInlineActivityView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Updating…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 16)
    }
}

struct DefaultErrorView: View {
    let error: ScreenError

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
            Text(error.title)
                .font(.title3.bold())
            Text(error.message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            if let retry = error.retry {
                Button("Retry", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct DefaultEmptyView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 34))
            Text("Nothing to show yet")
                .font(.title3.bold())
            Text("The operation succeeded, but there is no content to display.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct DefaultBannerView: View {
    let banner: BannerState
    let dismiss: () -> Void

    var body: some View {
        Text(banner.message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .onTapGesture(perform: dismiss)
    }

    private var backgroundColor: Color {
        switch banner.style {
        case .success: return .green
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

#endif
