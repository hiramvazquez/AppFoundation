import Foundation
import Observation
import os

// MARK: - NavigationLayer

/// Represents which navigation layer is currently active.
public nonisolated enum NavigationLayer: Equatable, Sendable {
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
public nonisolated struct StackState<Route: Hashable>: Equatable {
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

// MARK: - ModalState

/// The single modal layer a host can present (A5).
///
/// The coordinator models exactly what SwiftUI can render: at most ONE modal per host.
/// The style says how it is presented; the stack is the modal's own navigation.
public nonisolated struct ModalState<Route: Hashable>: Equatable {
    /// How the modal is presented.
    public var style: PresentationStyle

    /// The modal's own navigation stack.
    public var stack: StackState<Route>

    /// Creates a modal state with a fresh stack rooted at `root`.
    public init(style: PresentationStyle, root: Route) {
        self.style = style
        self.stack = StackState(root: root)
    }
}

// MARK: - Coordinator

/// Manages navigation flows using SwiftUI's `NavigationStack`.
///
/// `Coordinator` is the primary implementation of the `Router` protocol. It manages:
/// - the main stack for standard push navigation
/// - a single modal layer (`modal`) presented as sheet or full screen cover
///
/// ## Modal policy (A5 — documented and tested)
///
/// The state only models what SwiftUI can render: **one modal layer per host**.
/// Presenting while a modal is already visible **replaces** it (the previous modal and
/// its pushed path are discarded). If you need modal-over-modal, present a route whose
/// destination owns its own `Coordinator` and `CoordinatorView`.
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
@Observable
public final class Coordinator<Route: Hashable>: Router {
    // MARK: - Observable State

    /// The state of the main navigation stack.
    public var mainStack: StackState<Route>

    /// The single modal layer, if one is presented (A5).
    ///
    /// Writable so `CoordinatorView` can bind the modal's live path (A6); use
    /// `present(_:as:)` / `dismiss()` to change what is presented.
    public var modal: ModalState<Route>?

    // MARK: - Derived State

    /// Whether the coordinator is at the root view (no pushed routes, no modal).
    public var isAtRoot: Bool {
        mainStack.path.isEmpty && modal == nil
    }

    /// The currently active navigation layer.
    public var activeLayer: NavigationLayer {
        switch modal?.style {
        case nil: return .main
        case .sheet: return .sheet
        case .fullScreenCover: return .fullScreenCover
        }
    }

    /// Whether a sheet is currently presented.
    public var isSheetPresented: Bool { modal?.style == .sheet }

    /// Whether a full screen cover is currently presented.
    public var isFullScreenPresented: Bool { modal?.style == .fullScreenCover }

    /// The modal stack when presented as a sheet, `nil` otherwise.
    public var sheetStack: StackState<Route>? {
        modal?.style == .sheet ? modal?.stack : nil
    }

    /// The modal stack when presented as a full screen cover, `nil` otherwise.
    public var fullScreenStack: StackState<Route>? {
        modal?.style == .fullScreenCover ? modal?.stack : nil
    }

#if DEBUG
    /// Navigation history for debugging (only in DEBUG builds).
    ///
    /// Internal on purpose (AF-14): an API whose existence depends on the build
    /// configuration would break a consumer that references it in Release.
    @ObservationIgnored
    private(set) var navigationHistory: [String] = []
#endif

    // MARK: - Initialization

    /// Initializes a new coordinator with a root route.
    /// - Parameter root: The root route of the main navigation stack.
    public init(root: Route) {
        self.mainStack = StackState(root: root)
        log("Initialized with root", payload: "\(root)")
    }

    // MARK: - Router Conformance

    public func push(_ route: Route) {
        if modal != nil {
            modal?.stack.path.append(route)
        } else {
            mainStack.path.append(route)
        }
        log("Push →", payload: "\(route)")
    }

    public func pop() {
        if modal != nil {
            guard modal?.stack.path.isEmpty == false else { return }
            modal?.stack.path.removeLast()
        } else {
            guard !mainStack.path.isEmpty else { return }
            mainStack.path.removeLast()
        }
        log("Pop")
    }

    public func popToRoot() {
        if modal != nil {
            modal?.stack.path.removeAll()
        } else {
            mainStack.path.removeAll()
        }
        log("PopToRoot")
    }

    public func popTo(_ route: Route) {
        if modal != nil {
            guard var stack = modal?.stack else { return }
            Self.popStack(&stack, to: route)
            modal?.stack = stack
        } else {
            Self.popStack(&mainStack, to: route)
        }
        log("PopTo →", payload: "\(route)")
    }

    /// Presents `route` modally. If a modal is already presented, it is REPLACED —
    /// the previous modal and everything pushed on it are discarded (A5 policy).
    public func present(_ route: Route, as style: PresentationStyle) {
        if modal != nil {
            log("Present replaces existing modal")
        }
        modal = ModalState(style: style, root: route)
        log("Present \(style == .sheet ? "sheet" : "fullScreenCover") →", payload: "\(route)")
    }

    /// Dismisses the active modal, discarding its stack (A7: state never goes stale).
    public func dismiss() {
        guard modal != nil else { return }
        modal = nil
        log("Dismiss modal")
    }

    // MARK: - Coordinator-Specific Methods

    /// Sets a new root route, clearing the main path AND dismissing any modal —
    /// after `setRoot` the coordinator is fully at root.
    /// - Parameter route: The new root route.
    public func setRoot(_ route: Route) {
        modal = nil
        mainStack = StackState(root: route)
        log("Set root →", payload: "\(route)")
    }

    /// Replaces the entire main stack path with new routes.
    /// - Parameter routes: The new routes to set in the main stack path.
    public func setStack(_ routes: [Route]) {
        mainStack.path = routes
        log("Set stack →", payload: "\(routes)")
    }

    // MARK: - Private Helpers

    private nonisolated static func popStack(_ stack: inout StackState<Route>, to route: Route) {
        if let index = stack.path.lastIndex(of: route) {
            stack.path.removeLast(stack.path.count - index - 1)
        } else if stack.root == route {
            stack.path.removeAll()
        }
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
