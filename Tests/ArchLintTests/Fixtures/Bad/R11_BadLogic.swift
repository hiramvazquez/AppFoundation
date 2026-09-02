import AppFoundation
import Foundation

public protocol BadLogicProtocol: Logic {}

// Triggers ArchLint.R11 (warning, not error, M5): a Logic pinned to @MainActor loses its
// actor independence.
@MainActor
public final class BadLogic: BadLogicProtocol {
    public init() {}
}
