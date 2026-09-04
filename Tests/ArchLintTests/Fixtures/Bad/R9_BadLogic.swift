import AppFoundation
import Foundation

public protocol BadLogicProtocol: Logic {}

// Violates ArchLint.R9: a Logic referencing Router — navigation is the ViewModel's job.
public final class BadLogic: BadLogicProtocol {
    deinit {}
    private let router: Router

    public init(router: Router) {
        self.router = router
    }
}
