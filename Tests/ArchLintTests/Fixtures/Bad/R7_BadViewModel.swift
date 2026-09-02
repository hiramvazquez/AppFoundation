import AppFoundation
import Foundation

// Violates ArchLint.R7: an APIError reference reaching the ViewModel — it should stop at
// the Logic, translated to a DomainError (M1).
@MainActor
public final class BadViewModel: LogicViewModel<any BadLogicProtocol>, ActionHandling {
    public enum Action: Sendable { case load }
    public var lastError: APIError?
    public func handle(_ action: Action) {}
}
