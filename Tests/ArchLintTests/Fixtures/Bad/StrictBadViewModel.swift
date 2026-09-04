import AppFoundation
import Foundation
import Observation

// With `strict: true`, violates the extended ArchLint.R1: a ViewModel that inherits
// BaseViewModel directly instead of LogicViewModel<any XxxLogicProtocol>. Passes under the
// default (non-strict) config.
@MainActor
@Observable
public final class StrictBadViewModel: BaseViewModel, ActionHandling {
    public enum Action: Sendable { case load }
    public func handle(_ action: Action) {}
}
