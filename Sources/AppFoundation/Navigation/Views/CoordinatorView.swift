#if canImport(SwiftUI)
import SwiftUI

// MARK: - CoordinatorView

/// A SwiftUI view that renders navigation state managed by a `Coordinator`.
///
/// `CoordinatorView` renders the main `NavigationStack` plus the coordinator's single
/// modal layer (sheet or full screen cover). All bindings read the coordinator's LIVE
/// state (A6) — nothing is captured from a stale snapshot — and an interactive dismissal
/// (swipe-down) clears the modal state through `dismiss()` so it never goes stale (A7).
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

    @ViewBuilder
    private func routeView(_ route: Route) -> some View {
        content(route)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .navigationDestination(for: Route.self) { route in
                content(route)
                    #if os(iOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #endif
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
            get: { coordinator.modal?.style == style },
            set: { isPresented in
                if !isPresented, coordinator.modal?.style == style {
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
