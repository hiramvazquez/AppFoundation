#if canImport(SwiftUI)
import SwiftUI

// MARK: - Presentation Logic

/// Pure presentation decisions for `CoordinatorView`'s modal bindings, extracted from the
/// `Binding` closures in `modalPresentedBinding(for:)` so they're testable without
/// constructing a live `Coordinator`/SwiftUI hierarchy (same pattern as
/// `ScreenPresentationLogic` in `ScreenContainer.swift`).
nonisolated enum CoordinatorViewLogic {
    /// The `get` half of `modalPresentedBinding(for:)`: a `style`-specific sheet/full-screen
    /// binding reports "presented" only while the ACTIVE modal is that exact style — not
    /// merely "some modal exists" (that would present both the sheet AND the cover bindings
    /// at once whenever either is up).
    static func isPresented(currentModalStyle: PresentationStyle?, for style: PresentationStyle) -> Bool {
        currentModalStyle == style
    }

    /// The `set` half of `modalPresentedBinding(for:)`: SwiftUI calls every modifier's
    /// binding with `isPresented: false` on interactive dismissal, teardown, or simply
    /// because ITS style stopped being active (e.g. `.present(_:as: .fullScreenCover)`
    /// replaced a sheet — the sheet's own binding fires too). Only dismiss the coordinator
    /// when the modal that is being turned off is still the one actually presented (A7):
    /// otherwise a stale `.sheet` binding closing out from under a newer `.fullScreenCover`
    /// would dismiss the WRONG presentation.
    static func shouldDismiss(
        settingPresentedTo isPresented: Bool,
        currentModalStyle: PresentationStyle?,
        for style: PresentationStyle
    ) -> Bool {
        !isPresented && currentModalStyle == style
    }
}

// MARK: - CoordinatorView

/// A SwiftUI view that renders navigation state managed by a `Coordinator`.
///
/// `CoordinatorView` renders the main `NavigationStack` plus the coordinator's single
/// modal layer (sheet or full screen cover). All bindings read the coordinator's LIVE
/// state (A6) — nothing is captured from a stale snapshot — and an interactive dismissal
/// (swipe-down) clears the modal state through `dismiss()` so it never goes stale (A7).
///
/// The native navigation bar stays visible: screens own their chrome through
/// `navigationTitle`, `toolbar` and `searchable`, and opt out of it explicitly with
/// `ScreenContainer(chrome: .custom(...))`.
///
/// On macOS, full screen covers are presented as sheets (there is no
/// `fullScreenCover` on macOS; a sheet is window-modal there anyway).
///
/// ## Example
/// ```swift
/// struct ContentView: View {
///     @State private var coordinator = Coordinator<AppRoute>(root: .home)
///
///     var body: some View {
///         CoordinatorView(coordinator: coordinator) { route in
///             switch route {
///             case .home:
///                 HomeView()
///             case .detail(let id):
///                 DetailView(id: id)
///             }
///         }
///     }
/// }
/// ```
public struct CoordinatorView<Route: Hashable, Content: View>: View {
    // MARK: - Properties

    private let coordinator: Coordinator<Route>
    private let content: (Route) -> Content

    // MARK: - Initialization

    /// Initializes a coordinator view.
    /// - Parameters:
    ///   - coordinator: The coordinator managing navigation state.
    ///   - content: A view builder that creates a view for each route.
    public init(
        coordinator: Coordinator<Route>,
        @ViewBuilder content: @escaping (Route) -> Content
    ) {
        self.coordinator = coordinator
        self.content = content
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack(path: Bindable(coordinator).mainStack.path) {
            routeView(coordinator.mainStack.root)
        }
        #if os(iOS)
        .sheet(isPresented: modalPresentedBinding(for: .sheet)) {
            modalNavigationStack
        }
        .fullScreenCover(isPresented: modalPresentedBinding(for: .fullScreenCover)) {
            modalNavigationStack
        }
        #else
        .sheet(isPresented: anyModalPresentedBinding) {
            modalNavigationStack
        }
        #endif
    }

    // MARK: - Private Views

    /// Native chrome by default (AF-12/AF-13): the coordinator never hides the
    /// navigation bar. Each screen decides — `navigationTitle`/`toolbar`/`searchable`
    /// on the native bar, or `ScreenContainer(chrome: .custom(...))` to opt out.
    @ViewBuilder
    private func routeView(_ route: Route) -> some View {
        content(route)
            .navigationDestination(for: Route.self) { route in
                content(route)
            }
    }

    @ViewBuilder
    private var modalNavigationStack: some View {
        if let root = coordinator.modal?.stack.root {
            NavigationStack(path: modalPathBinding) {
                routeView(root)
            }
        }
    }

    // MARK: - Live Bindings (A6/A7)

    /// Binds the modal's path against the coordinator's CURRENT state — no snapshot.
    private var modalPathBinding: Binding<[Route]> {
        Binding(
            get: { coordinator.modal?.stack.path ?? [] },
            set: { coordinator.modal?.stack.path = $0 }
        )
    }

    /// Presents when the modal has the given style; setting `false` (interactive
    /// dismissal included) clears the modal state through `dismiss()` (A7).
    private func modalPresentedBinding(for style: PresentationStyle) -> Binding<Bool> {
        Binding(
            get: { CoordinatorViewLogic.isPresented(currentModalStyle: coordinator.modal?.style, for: style) },
            set: { isPresented in
                if CoordinatorViewLogic.shouldDismiss(
                    settingPresentedTo: isPresented,
                    currentModalStyle: coordinator.modal?.style,
                    for: style
                ) {
                    coordinator.dismiss()
                }
            }
        )
    }

    /// macOS: any modal renders as a sheet.
    private var anyModalPresentedBinding: Binding<Bool> {
        Binding(
            get: { coordinator.modal != nil },
            set: { isPresented in
                if !isPresented {
                    coordinator.dismiss()
                }
            }
        )
    }
}

#endif
