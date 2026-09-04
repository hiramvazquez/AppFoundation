import AppFoundation
import Foundation

// Violates ArchLint.R6: `init` receives a CONCRETE Logic type instead of `any
// XxxLogicProtocol`.
@MainActor
public final class BadViewModel: ActionHandling {
    deinit {}
    public enum Action: Sendable { case load }

    public init(logic: BadLogic) {}

    public func handle(_ action: Action) {}
}
