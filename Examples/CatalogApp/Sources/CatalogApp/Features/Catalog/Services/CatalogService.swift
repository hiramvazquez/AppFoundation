import CoreNetworking
import Foundation

// MARK: - The request / response DTOs (M2: only this file ever sees them)

/// A typed endpoint the way CoreNetworking wants it. `Response`/`ItemDTO` are DTOs —
/// `CatalogService` maps them to `Item` (the domain model) before returning;
/// `CatalogLogic`/`CatalogViewModel` never see them.
struct GetCatalogRequest: BaseRequest {
    struct ItemDTO: Decodable, Sendable {
        let id: UUID
        let title: String
    }

    struct Response: Decodable, Sendable {
        let items: [ItemDTO]
    }

    let path = "/catalog"
    let method = HTTPMethod.get
}

// MARK: - The service

/// One API call: `GET /catalog` → `[Item]`. `CatalogServicing` is what `CatalogLogic`
/// depends on through `init` — never this concrete type
/// (`ARQUITECTURA-KIT-2026-09-02.md` §1, rule 3). `struct Sendable` (M5).
public protocol CatalogServicing: Sendable {
    func fetchItems() async throws(APIError) -> [Item]
}

/// The ONLY type in this app that references `APIServiceProtocol`/`BaseRequest` for the
/// catalog endpoint.
public struct CatalogService: CatalogServicing, EndpointService {
    public let api: any APIServiceProtocol

    public init(api: any APIServiceProtocol) {
        self.api = api
    }

    public func fetchItems() async throws(APIError) -> [Item] {
        let response = try await call(GetCatalogRequest())
        return response.items.map { Item(id: $0.id, title: $0.title) }
    }
}
