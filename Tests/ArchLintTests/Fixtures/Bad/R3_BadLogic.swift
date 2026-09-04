import AppFoundation
import CoreNetworking
import Foundation

public protocol BadLogicProtocol: Logic {
    func load() async throws -> String
}

// Violates ArchLint.R3: a Logic touching APIServiceProtocol/BaseRequest directly instead
// of going through a Service.
public final class BadLogic: BadLogicProtocol {
    deinit {}
    private let api: any APIServiceProtocol

    public init(api: any APIServiceProtocol) {
        self.api = api
    }

    public func load() async throws -> String {
        struct Req: BaseRequest {
            let path = "/x"
            let method = HTTPMethod.get
        }
        return try await api.execute(Req())
    }
}
