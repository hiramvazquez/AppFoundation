import AppFoundation
import CoreNetworking
import Foundation
import SwiftData

/// Registers the Catalog feature into a `Container`: the composition root is the only
/// place that knows `CatalogService`/`SwiftDataCatalogStore`/`ModelContainer` behind their
/// protocols (M4).
///
/// ```swift
/// Container.shared.register(modules: [try! CatalogModule(baseURL: url)])
/// // Root view:
/// CatalogView(viewModel: Container.shared.resolve())
/// ```
public struct CatalogModule: DependencyModule {
    private let baseURL: URL
    private let modelContainer: ModelContainer

    /// - Parameters:
    ///   - baseURL: The catalog API's base URL.
    ///   - modelContainer: Defaults to a persisted, on-disk container for `ItemRecord`.
    ///     Tests pass an in-memory one instead.
    public init(baseURL: URL, modelContainer: ModelContainer? = nil) throws {
        self.baseURL = baseURL
        self.modelContainer = try modelContainer ?? ModelContainer(for: ItemRecord.self)
    }

    public func register(in container: Container) {
        container.register(APIServiceProtocol.self) { [baseURL] _ in
            APIService(configuration: NetworkingConfiguration(baseURL: baseURL))
        }
        container.register(CatalogServicing.self) { c in
            CatalogService(api: c.resolve())
        }
        container.register(CatalogStoring.self) { [modelContainer] _ in
            SwiftDataCatalogStore(modelContainer: modelContainer)
        }
        container.register(CatalogLogicProtocol.self) { c in
            CatalogLogic(catalogService: c.resolve(), catalogStore: c.resolve())
        }
        container.register(CatalogViewModel.self, lifecycle: .transient) { c in
            CatalogViewModel(logic: c.resolve())
        }
    }
}
