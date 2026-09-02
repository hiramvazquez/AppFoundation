import Foundation

/// The single entry point for a screen's user actions (AF-05,
/// `AUDITORIA-2026-09-01.md` — decisión del propietario). A view model conforms to
/// `ActionHandling` instead of exposing its methods to the view directly: `Action` is
/// usually an `enum` naming every gesture the screen recognizes (`.load`, `.refresh`,
/// `.rowTapped(id:)`), and `handle(_:)` is the ONLY method the view — or a test standing in
/// for one — calls. Everything else on the view model can be `private`.
///
/// ```swift
/// @Observable
/// final class ProfileViewModel: BaseViewModel, ActionHandling {
///     enum Action: Sendable {
///         case load
///         case refresh
///     }
///
///     private(set) var profile: Profile?
///     private let repository: ProfileRepository
///
///     init(repository: ProfileRepository) {
///         self.repository = repository
///         super.init()
///     }
///
///     func handle(_ action: Action) {
///         switch action {
///         case .load: load()
///         case .refresh: refresh()
///         }
///     }
///
///     private func load() {
///         performLoad { vm in vm.profile = try await vm.repository.fetchProfile() }
///     }
///
///     private func refresh() {
///         performActivity(style: .overlay) { vm in
///             vm.profile = try await vm.repository.fetchProfile()
///         }
///     }
/// }
/// ```
///
/// Tests call `vm.handle(.load)` — the same call the view makes — never `vm.load()`
/// directly, which is what makes `handle(_:)` testable without `@testable import` to reach
/// past `private`.
@MainActor
public protocol ActionHandling: AnyObject {
    /// Every action the screen recognizes. `Sendable` because `ActionSender` crosses into
    /// `@ViewBuilder` content closures.
    associatedtype Action: Sendable

    /// Handles a single user action. The only method a view should call.
    func handle(_ action: Action)
}

extension ActionHandling {
    /// The `ActionSender` `ScreenContainer` hands to its content closure: wraps
    /// `handle(_:)` behind a `weak` reference to `self`, so a view can hold on to a sender
    /// without keeping the view model alive — the same memory contract `performLoad`
    /// already upholds (see `BaseViewModelMemoryTests`).
    public var sender: ActionSender<Action> {
        ActionSender { [weak self] action in
            self?.handle(action)
        }
    }
}

/// The ONLY thing a `ScreenContainer` content closure receives to act on the screen: it
/// cannot call methods on the view model directly, because it never sees the view model —
/// only this. `sender(.load)` (via `callAsFunction`) and `sender.send(.load)` do the same
/// thing; `callAsFunction` reads better at the call site, `send` is there for call sites
/// that prefer a named method (e.g. passing it around as a value: `let send = sender.send`).
///
/// Built through `ActionHandling.sender`, so it captures its view model **weakly**: a view
/// can outlive the view model without retaining it.
public struct ActionSender<Action: Sendable>: Sendable {
    private let handler: @MainActor @Sendable (Action) -> Void

    public init(_ handler: @escaping @MainActor @Sendable (Action) -> Void) {
        self.handler = handler
    }

    /// `sender(.load)`.
    @MainActor
    public func callAsFunction(_ action: Action) {
        handler(action)
    }

    /// `sender.send(.load)` — explicit alias for `callAsFunction`.
    @MainActor
    public func send(_ action: Action) {
        handler(action)
    }
}

/// A screen view model: observable state (`ScreenState`) plus a single action entry point
/// (`ActionHandling`). `ScreenContainer(_:chrome:content:)` requires this — not the concrete
/// `BaseViewModel` class — so any `@Observable final class` that conforms compiles against
/// the shell, with or without inheriting from `BaseViewModel`.
public typealias ScreenViewModel = ScreenState & ActionHandling
