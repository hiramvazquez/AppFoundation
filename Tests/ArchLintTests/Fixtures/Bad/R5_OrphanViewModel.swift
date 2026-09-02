import AppFoundation
import Foundation

// Violates ArchLint.R5: there is no OrphanLogic.swift alongside this file.
@MainActor
public final class OrphanViewModel: LogicViewModel<any OrphanLogicProtocol>, ActionHandling {
    public enum Action: Sendable { case load }
    public func handle(_ action: Action) {}
}
