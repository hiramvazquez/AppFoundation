#if canImport(SwiftUI)
import SwiftUI

/// A lightweight container view that displays content based on ViewPhase without navigation.
///
/// `PhaseView` provides phase-based content switching for screens without navigation chrome.
/// It handles the four main phases:
/// - **idle**: Initial state, displays content normally
/// - **loading**: Shows loading indicator
/// - **content**: Displays main content
/// - **empty**: Shows empty state view
/// - **error**: Shows error view with optional retry
///
/// This is a simpler alternative to `ScreenContainer` for screens that don't need
/// navigation chrome at all (`ScreenContainer` with `chrome: .native` is usually the
/// better fit once a screen sits in a `NavigationStack`).
///
/// Loading/error/empty appearances come from `Environment` (`LoadingViewStyle`,
/// `ErrorViewStyle`, `EmptyViewStyle` — the same styles `ScreenContainer` reads), installed
/// with `.loadingViewStyle(_:)`/`.errorViewStyle(_:)`/`.emptyViewStyle(_:)`. There is no
/// per-instance builder closure to override them (AF-15): a style is composable and
/// type-erasure-free at the call site, unlike a closure stored on the view.
///
/// ## Example
/// ```swift
/// @State var phase: ViewPhase = .idle
///
/// PhaseView(phase: $phase) {
///     ContentView()
/// }
/// .errorViewStyle(MyErrorStyle())
/// ```
public struct PhaseView<Content: View>: View {
    @Binding private var phase: ViewPhase
    private let content: () -> Content
    private let backgroundColor: Color

    @Environment(\.loadingViewStyle) private var loadingStyle
    @Environment(\.errorViewStyle) private var errorStyle
    @Environment(\.emptyViewStyle) private var emptyStyle

    /// Creates a phase view with bindings to view model state.
    ///
    /// - Parameters:
    ///   - phase: Binding to the current ViewPhase
    ///   - backgroundColor: Background color (defaults to system background)
    ///   - content: The main content view
    public init(
        phase: Binding<ViewPhase>,
        backgroundColor: Color = .platformBackground,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._phase = phase
        self.backgroundColor = backgroundColor
        self.content = content
    }

    /// Creates a phase view observing a `ScreenState` (AF-05) — most often a
    /// `BaseViewModel` subclass — without needing a `Binding` to its `phase` property.
    /// `PhaseView` never writes back to `phase`, so this reads it directly.
    public init(
        observing state: some ScreenState,
        backgroundColor: Color = .platformBackground,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            phase: Binding(get: { state.phase }, set: { _ in }),
            backgroundColor: backgroundColor,
            content: content
        )
    }

    public var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            if !ScreenPresentationLogic.hidesContent(phase) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            switch ScreenPresentationLogic.phaseOverlay(for: phase) {
            case .none:
                EmptyView()

            case .loading(let style):
                loadingOverlay(style: style)

            case .empty:
                emptyStyle.makeBody(configuration: EmptyConfiguration())

            case .error(let error):
                errorStyle.makeBody(configuration: ErrorConfiguration(error: error))
            }
        }
        .animation(.default, value: phase)
    }

    /// Every loading style renders something — `.inline` keeps content visible with an
    /// inline indicator on top (A2 is impossible here by construction).
    @ViewBuilder
    private func loadingOverlay(style: ActivityStyle) -> some View {
        let loadingBody = loadingStyle.makeBody(configuration: LoadingConfiguration(style: style))
        switch ScreenPresentationLogic.activityContainer(for: style) {
        case .opaque, .dimmed:
            loadingBody
        case .topAligned:
            VStack {
                loadingBody
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("PhaseView · content") {
    PhaseView(phase: .constant(.content)) {
        ScrollView {
            VStack {
                ForEach(0..<20, id: \.self) { i in
                    Text("Item \(i)")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.platformSecondaryBackground)
                }
            }
        }
    }
}

#Preview("PhaseView · loading") {
    PhaseView(phase: .constant(.loading(.fullScreen))) {
        Text("Hidden content")
    }
}

#Preview("PhaseView · empty") {
    PhaseView(phase: .constant(.empty)) {
        Text("Hidden content")
    }
}

#Preview("PhaseView · error") {
    PhaseView(
        phase: .constant(
            .error(
                ScreenError(
                    title: "Network Error",
                    message: "Unable to connect. Please try again.",
                    retry: {}
                )
            )
        )
    ) {
        Text("Hidden content")
    }
}
#endif

#endif
