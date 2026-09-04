import AppFoundation
import CoreNetworking
import Foundation
import Observation

// Violates ArchLint.R1 twice: imports CoreNetworking, and references APIService directly
// instead of going through `any XxxLogicProtocol`.
@Observable
public final class BadViewModel: LogicViewModel<any BadLogicProtocol> {
    deinit {}
    private let api: APIService

    public init(api: APIService, logic: any BadLogicProtocol) {
        self.api = api
        super.init(logic: logic)
    }
}
