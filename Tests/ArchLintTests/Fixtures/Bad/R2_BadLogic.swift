import AppFoundation
import SwiftUI

// Violates ArchLint.R2: imports SwiftUI and references a *ViewModel type. Also missing its
// own `protocol XxxLogicProtocol: Logic` declaration.
public final class BadLogic {
    deinit {}
    func present(_ viewModel: BadViewModel) {}
}
