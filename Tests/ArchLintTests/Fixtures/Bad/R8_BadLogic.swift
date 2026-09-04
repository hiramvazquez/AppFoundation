import AppFoundation
import Foundation

public protocol BadLogicProtocol: Logic {
    func load() async throws -> String
}

// Violates ArchLint.R8: a Logic returning a raw DTO (*Response) instead of mapping it to a
// domain model inside the Service/Store.
public final class BadLogic: BadLogicProtocol {
    deinit {}
    func load() async throws -> String {
        let response: GetBadRequest.Response = try await fetch()
        return response.title
    }

    private func fetch() async throws -> GetBadRequest.Response {
        fatalError()
    }
}
