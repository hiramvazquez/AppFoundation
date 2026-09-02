#if canImport(SwiftUI)
import SwiftUI

/// A lightweight container view that displays content based on ViewPhase without navigation.
///
/// `PhaseView` provides phase-based content switching for screens without navigation bars.
/// It handles the four main phases:
/// - **idle**: Initial state, displays content normally
/// - **loading**: Shows loading indicator
/// - **content**: Displays main content
/// - **empty**: Shows empty state view
/// - **error**: Shows error view with optional retry
///
/// This is a simpler alternative to `ScreenContainer` for screens that don't need custom navigation.
///
/// ## Example
/// ```swift
/// @State var viewModel = MyViewModel()
///
/// PhaseView(phase: $viewModel.phase) {
///     ContentView()
/// }
/// .loadingView {
///     MyCustomLoadingView()
/// }
/// .errorView { error in
///     MyCustomErrorView(error: error)
/// }
/// ```
public struct PhaseView<Content: View>: View {
    @Binding private var phase: ViewPhase
    private let content: () -> Content
    private let backgroundColor: Color

    // Custom overlay builders
    private var loadingViewBuilder: (() -> AnyView)?
    private var errorViewBuilder: ((ScreenError) -> AnyView)?
    private var emptyViewBuilder: (() -> AnyView)?

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
                if let builder = emptyViewBuilder {
                    builder()
                } else {
                    DefaultEmptyView()
                }

            case .error(let error):
                if let builder = errorViewBuilder {
                    builder(error)
                } else {
                    DefaultErrorView(error: error)
                }
            }
        }
        .animation(.default, value: phase)
    }

    /// Every loading style renders something — `.inline` keeps content visible with an
    /// inline indicator on top (A2 is impossible here by construction).
    @ViewBuilder
    private func loadingOverlay(style: ActivityStyle) -> some View {
        switch style {
        case .fullScreen, .overlay:
            if let builder = loadingViewBuilder {
                builder()
            } else {
                DefaultLoadingView()
            }
        case .inline:
            VStack {
                if let builder = loadingViewBuilder {
                    builder()
                } else {
                    DefaultInlineActivityView()
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Custom View Builders

    /// Sets a custom loading view.
    public func loadingView<V: View>(@ViewBuilder builder: @escaping () -> V) -> Self {
        var copy = self
        copy.loadingViewBuilder = { AnyView(builder()) }
        return copy
    }

    /// Sets a custom error view.
    public func errorView<V: View>(@ViewBuilder builder: @escaping (ScreenError) -> V) -> Self {
        var copy = self
        copy.errorViewBuilder = { AnyView(builder($0)) }
        return copy
    }

    /// Sets a custom empty state view.
    public func emptyView<V: View>(@ViewBuilder builder: @escaping () -> V) -> Self {
        var copy = self
        copy.emptyViewBuilder = { AnyView(builder()) }
        return copy
    }
}

// MARK: - Preview

#if DEBUG
struct PhaseView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Content state
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
            .previewDisplayName("Content")

            // Loading state
            PhaseView(phase: .constant(.loading(.fullScreen))) {
                Text("Hidden content")
            }
            .previewDisplayName("Loading")

            // Empty state
            PhaseView(phase: .constant(.empty)) {
                Text("Hidden content")
            }
            .previewDisplayName("Empty")

            // Error state
            PhaseView(
                phase: .constant(
                    .error(ScreenError(
                        title: "Network Error",
                        message: "Unable to connect. Please try again.",
                        retry: {}
                    ))
                )
            ) {
                Text("Hidden content")
            }
            .previewDisplayName("Error")
        }
    }
}
#endif

#endif
