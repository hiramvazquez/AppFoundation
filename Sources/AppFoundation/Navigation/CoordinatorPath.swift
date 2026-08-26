import Foundation

/// Convenience alias for route enumerations used with `Coordinator`.
/// Routes must conform to `Hashable` and `Identifiable` so they can be stored in navigation stacks.
public typealias CoordinatorPath = Hashable & Identifiable
