import CoreNetworking
import Foundation

struct GetLoginRequest: BaseRequest {
    struct ItemDTO: Decodable, Sendable {
        let id: UUID
        let title: String
    }

    struct Response: Decodable, Sendable {
        let items: [ItemDTO]
    }

    let path = "/login"
    let method = HTTPMethod.get
}

public protocol LoginServicing: Sendable {
    func fetchItems() async throws(APIError) -> [LoginItem]
}

public struct LoginService: LoginServicing, EndpointService {
    public let api: any APIServiceProtocol

    public init(api: any APIServiceProtocol) {
        self.api = api
    }

    public func fetchItems() async throws(APIError) -> [LoginItem] {
        let response = try await call(GetLoginRequest())
        return response.items.map { LoginItem(id: $0.id, title: $0.title) }
    }
}
