import Foundation
import os

// MARK: - NavigationLayer

/// Represents which navigation layer is currently active.
public enum NavigationLayer: Equatable, Sendable {
    /// The main navigation stack.
    case main

    /// A sheet (modal) presentation.
    case sheet

    /// A full screen cover presentation.
    case fullScreenCover
}

// MARK: - StackState

/// Represents the state of a navigation stack.
///
/// A stack consists of a root view and a path of additional routes that have been pushed.
public struct StackState<Route: Hashable>: Equatable {
    /// The root route of this stack.
    public var root: Route

    /// The path of routes that have been pushed onto this stack.
    public var path: [Route]

    /// Initializes a new stack state.
    /// - Parameters:
    ///   - root: The root route.
    ///   - path: The initial path of routes (default is empty).
    public init(root: Route, path: [Route] = []) {
        self.root = root
        self.path = path
    }
}

// MARK: - Coordinator

/// Manages navigation flows using SwiftUI's `NavigationStack`.
///
/// `Coordinator` is the primary implementation of the `Router` protocol.
/// It manages three independent navigation stacks:
/// - Main stack for standard push navigation
/// - Sheet stack for modal sheet presentations
/// - Full screen cover stack for opaque modal presentations
///
/// The coordinator is designed to be owned by a dependency injection container
/// or app state manager, and injected into views and view models via the `Router` protocol.
///
/// ## Example
/// ```swift
/// let coordinator = Coordinator<AppRoute>(root: .home)
///
/// // In a view model
/// func goToDetail() {
///     router.push(.detail(id: 123))
/// }
/// ```
@MainActor
public final class Coordinator<Route: Hashable>: ObservableObject, Router {
    // MARK: - Published Properties

    /// The state of the main navigation stack.
    @Published public var mainStack: StackState<Route> { didSet { recalculateIsAtRoot() } }

    /// The state of the sheet presentation stack, if one is active.
    @Published public var sheetStack: StackState<Route>? { didSet { recalculateIsAtRoot() } }

    /// The state of the full screen cover stack, if one is active.
    @Published public var fullScreenStack: StackState<Route>? { didSet { recalculateIsAtRoot() } }

    /// Whether a sheet is currently presented.
    @Published public var isSheetPresented: Bool = false { didSet { recalculateIsAtRoot() } }

    /// Whether a full screen cover is currently presented.
    @Published public var isFullScreenPresented: Bool = false { didSet { recalculateIsAtRoot() } }

    /// Whether the coordinator is at the root view (no navigation stack, no modals).
    @Published public private(set) var isAtRoot: Bool = true

    // MARK: - Internal Properties

    /// Tracks the last presented modal layer to resolve priority when both are active.
    private var lastPresentedModalLayer: NavigationLayer = .main

#if DEBUG
    /// Navigation history for debugging (only in DEBUG builds).
    public private(set) var navigationHistory: [String] = []
#endif

    // MARK: - Initialization

    /// Initializes a new coordinator with a root route.
    /// - Parameter root: The root route of the main navigation stack.
    public init(root: Route) {
        self.mainStack = StackState(root: root)
        recalculateIsAtRoot()
        log("Initialized with root", payload: "\(root)")
    }

    // MARK: - Router Conformance

    public func push(_ route: Route) {
        switch activeLayer {
        case .main:
            mainStack.path.append(route)
        case .sheet:
            sheetStack?.path.append(route)
        case .fullScreenCover:
            fullScreenStack?.path.append(route)
        }
        log("Push →", payload: "\(route)")
    }

    public func pop() {
        switch activeLayer {
        case .main:
            guard !mainStack.path.isEmpty else { return }
            mainStack.path.removeLast()
        case .sheet:
            guard !(sheetStack?.path.isEmpty ?? true) else { return }
            sheetStack?.path.removeLast()
        case .fullScreenCover:
            guard !(fullScreenStack?.path.isEmpty ?? true) else { return }
            fullScreenStack?.path.removeLast()
        }
        log("Pop")
    }

    public func popToRoot() {
        switch activeLayer {
        case .main:
            mainStack.path.removeAll()
        case .sheet:
            sheetStack?.path.removeAll()
        case .fullScreenCover:
            fullScreenStack?.path.removeAll()
        }
        log("PopToRoot")
    }

    public func popTo(_ route: Route) {
        switch activeLayer {
        case .main:
            if let index = mainStack.path.lastIndex(of: route) {
                mainStack.path.removeLast(mainStack.path.count - index - 1)
            } else if mainStack.root == route {
                mainStack.path.removeAll()
            }
        case .sheet:
            if let index = sheetStack?.path.lastIndex(of: route) {
                sheetStack?.path.removeLast((sheetStack?.path.count ?? 0) - index - 1)
            } else if sheetStack?.root == route {
                sheetStack?.path.removeAll()
            }
        case .fullScreenCover:
            if let index = fullScreenStack?.path.lastIndex(of: route) {
                fullScreenStack?.path.removeLast((fullScreenStack?.path.count ?? 0) - index - 1)
            } else if fullScreenStack?.root == route {
                fullScreenStack?.path.removeAll()
            }
        }
        log("PopTo →", payload: "\(route)")
    }

    public func present(_ route: Route, as style: PresentationStyle) {
        switch style {
        case .sheet:
            sheetStack = StackState(root: route)
            isSheetPresented = true
            lastPresentedModalLayer = .sheet
            log("Present sheet →", payload: "\(route)")
        case .fullScreenCover:
            fullScreenStack = StackState(root: route)
            isFullScreenPresented = true
            lastPresentedModalLayer = .fullScreenCover
            log("Present fullScreenCover →", payload: "\(route)")
        }
    }

    public func dismiss() {
        switch activeLayer {
        case .fullScreenCover:
            isFullScreenPresented = false
            fullScreenStack = nil
        case .sheet:
            isSheetPresented = false
            sheetStack = nil
        case .main:
            break
        }
        log("Dismiss modal")
    }

    // MARK: - Coordinator-Specific Methods

    /// Sets the root route and clears all navigation stacks.
    /// - Parameter route: The new root route.
    public func setRoot(_ route: Route) {
        mainStack = StackState(root: route)
        log("Set root →", payload: "\(route)")
    }

    /// Replaces the entire main stack path with new routes.
    /// - Parameter routes: The new routes to set in the main stack path.
    public func setStack(_ routes: [Route]) {
        mainStack.path = routes
        log("Set stack →", payload: "\(routes)")
    }

    // MARK: - Computed Properties

    /// The currently active navigation layer.
    public var activeLayer: NavigationLayer {
        if isSheetPresented && isFullScreenPresented { return lastPresentedModalLayer }
        if isSheetPresented { return .sheet }
        if isFullScreenPresented { return .fullScreenCover }
        return .main
    }

    // MARK: - Private Helpers

    private func recalculateIsAtRoot() {
        isAtRoot = mainStack.path.isEmpty && !isFullScreenPresented && !isSheetPresented
    }

    /// Logs a navigation event.
    ///
    /// `operation` is static text (safe to expose); `payload` carries route values and is
    /// logged with `privacy: .private` so user-identifying route parameters (ids, names)
    /// are redacted outside of debugging sessions.
    private func log(_ operation: String, payload: String? = nil) {
#if DEBUG
        if let payload {
            AppFoundationLogger.navigation.debug("\(operation, privacy: .public) \(payload, privacy: .private)")
            navigationHistory.append("\(operation) \(payload)")
        } else {
            AppFoundationLogger.navigation.debug("\(operation, privacy: .public)")
            navigationHistory.append(operation)
        }
#endif
    }
}
