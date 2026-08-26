#if canImport(SwiftUI)
import SwiftUI

/// Defines where the custom navigation bar is rendered relative to screen content.
public enum NavigationPlacement {
    /// Navigation bar participates in normal vertical layout (default).
    case stack
    /// Navigation bar is overlaid and remains fixed while content scrolls beneath.
    case overlay
}

/// A screen shell with navigation chrome, screen-phase rendering, and feedback overlays.
///
/// `ScreenContainer` intentionally keeps a small public API while internally separating:
/// - base shell layout
/// - primary screen phase rendering (`phase`)
/// - transient activity overlays (`activity`)
/// - user feedback overlays (`alert`, `banner`)
public struct ScreenContainer<Content: View>: View {
    @Binding private var phase: ViewPhase
    @Binding private var loadingStyle: LoadingStyle
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
        self._phase = .init(get: { viewModel.phase }, set: { viewModel.phase = $0 })
        self._loadingStyle = .init(get: { viewModel.loadingStyle }, set: { viewModel.loadingStyle = $0 })
        self._activity = .init(get: { viewModel.activity }, set: { viewModel.activity = $0 })
        self._alert = .init(get: { viewModel.alert }, set: { viewModel.alert = $0 })
        self._banner = .init(get: { viewModel.banner }, set: { viewModel.banner = $0 })
        self.navigation = navigation
        self.navigationPlacement = navigationPlacement
        self.content = content
        self.backgroundColor = backgroundColor
    }

    /// Creates a screen container using explicit bindings.
    public init(
        phase: Binding<ViewPhase>,
        loadingStyle: Binding<LoadingStyle> = .constant(.fullScreen),
        activity: Binding<ActivityState> = .constant(.none),
        alert: Binding<AlertState?> = .constant(nil),
        banner: Binding<BannerState?> = .constant(nil),
        navigation: NavigationBarConfiguration = .hidden,
        navigationPlacement: NavigationPlacement = .stack,
        backgroundColor: Color = .platformBackground,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._phase = phase
        self._loadingStyle = loadingStyle
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
        ZStack {
            backgroundColor.ignoresSafeArea()

            mainContentView

            primaryPhaseOverlay

            activityOverlay

            if alert != nil {
                alertOverlayView
                    .transition(.opacity)
            }

            if banner != nil {
                bannerOverlayView
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        #if os(iOS)
        .navigationBarHidden(true)
        #endif
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
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(shouldHideContentForPrimaryPhase ? 0 : 1)
            .accessibilityHidden(shouldHideContentForPrimaryPhase)
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

    private var shouldHideContentForPrimaryPhase: Bool {
        switch phase {
        case .error, .empty:
            return true
        case .loading:
            return loadingStyle == .fullScreen
        case .idle, .content:
            return false
        }
    }

    // MARK: - Phase and Activity Rendering

    @ViewBuilder
    private var primaryPhaseOverlay: some View {
        switch phase {
        case .idle, .content:
            EmptyView()
        case .loading:
            if loadingStyle != .inline {
                loadingOverlayView(style: loadingStyle)
                    .transition(.opacity)
            }
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
        switch activity {
        case .none:
            EmptyView()
        case .loading(let style):
            switch style {
            case .inline:
                VStack {
                    DefaultInlineActivityView()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            case .overlay:
                ZStack {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    DefaultLoadingView()
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Overlay Views

    @ViewBuilder
    private func loadingOverlayView(style: LoadingStyle) -> some View {
        switch style {
        case .fullScreen:
            ZStack {
                backgroundColor.ignoresSafeArea()
                builtLoadingView
            }
        case .inline:
            VStack {
                builtLoadingView
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .overlay:
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                builtLoadingView
            }
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

    @ViewBuilder
    private var alertOverlayView: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { }

            if let alertState = alert {
                if let builder = alertViewBuilder {
                    builder(alertState)
                } else {
                    DefaultAlertView(alert: alertState) {
                        self.alert = nil
                    }
                }
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
        onSearchSubmit: (() -> Void)? = nil,
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

public typealias ScreenShell<Content: View> = ScreenContainer<Content>

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

struct DefaultAlertView: View {
    let alert: AlertState
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(alert.title)
                .font(.headline)
            Text(alert.message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if let secondary = alert.secondaryButton {
                    Button(secondary.title) {
                        secondary.action()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }

                Button(alert.primaryButton.title) {
                    alert.primaryButton.action()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
