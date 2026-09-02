import AppFoundation
import Foundation

public protocol BadLogicProtocol: Logic {}

// Violates ArchLint.R10 three ways: `Container.shared`, `resolve(`, and `@Inject`, all
// outside the composition root (XxxModule).
public final class BadLogic: BadLogicProtocol {
    @Inject var something: String

    func load() {
        let service = Container.shared.resolve(BadServicing.self)
        _ = service
    }
}
