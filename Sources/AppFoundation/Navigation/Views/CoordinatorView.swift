#if canImport(SwiftUI)
import SwiftUI

// MARK: - CoordinatorView

/// A SwiftUI view that renders navigation stacks managed by a `Coordinator`.
///
/// `CoordinatorView` creates a navigation hierarchy with three layers:
/// - Main stack: Standard push navigation
/// - Sheet: Modal sheet presentation
/// - Full screen cover: Opaque modal presentation
///
/// The view automatically synchronizes with the coordinator's state and renders
/// the appropriate routes using a provided content builder.
///
/// Use `@ObservedObject` when the coordinator is owned externally (e.g., by a DI container),
/// and `@StateObject` only when you own the coordinator within the view.
///
/// ## Example
/// ```swift
/// struct ContentView: View {
///     @StateObject var coordinator = Coordinator<AppRoute>(root: .home)
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

    @ObservedObject private var coordinator: Coordinator<Route>
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
        mainNavigationStack
            .sheet(isPresented: $coordinator.isSheetPresented) {
                sheetNavigationStack
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $coordinator.isFullScreenPresented) {
                fullScreenNavigationStack
            }
            #endif
    }

    // MARK: - Private Views

    private var mainNavigationStack: some View {
        NavigationStack(path: $coordinator.mainStack.path) {
            content(coordinator.mainStack.root)
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
    }

    private var sheetNavigationStack: some View {
        Group {
            if let sheetState = coordinator.sheetStack {
                NavigationStack(path: Binding(
                    get: { sheetState.path },
                    set: { coordinator.sheetStack?.path = $0 }
                )) {
                    content(sheetState.root)
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
            }
        }
    }

    private var fullScreenNavigationStack: some View {
        Group {
            if let fullScreenState = coordinator.fullScreenStack {
                NavigationStack(path: Binding(
                    get: { fullScreenState.path },
                    set: { coordinator.fullScreenStack?.path = $0 }
                )) {
                    content(fullScreenState.root)
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
            }
        }
    }
}

#endif
