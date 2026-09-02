import CoreNetworking
import CoreNetworkingTestSupport
import Foundation
import Testing

@testable import CatalogApp

/// `CatalogService` — the only type in this app that touches `APIServiceProtocol` — tested
/// against `MockAPIService`.
@Suite("CatalogService")
struct CatalogServiceTests {
    @Test("A stubbed 200 decodes DTOs into domain Items")
    func stubbedSuccessDecodesItems() async throws {
        let mock = MockAPIService()
        let id = UUID()
        mock.stub(
            GetCatalogRequest.self,
            returning: GetCatalogRequest.Response(items: [GetCatalogRequest.ItemDTO(id: id, title: "Widget")])
        )
        let service = CatalogService(api: mock)

        let items = try await service.fetchItems()

        #expect(items == [Item(id: id, title: "Widget")])
    }

    @Test("A stubbed failure propagates as APIError")
    func stubbedFailurePropagates() async {
        let mock = MockAPIService()
        mock.stub(GetCatalogRequest.self, throwing: .stub(code: .httpStatus, statusCode: 500))
        let service = CatalogService(api: mock)

        do {
            _ = try await service.fetchItems()
            Issue.record("Expected fetchItems() to throw")
        } catch {
            #expect(error.statusCode == 500)
        }
    }
}
