import AppFoundation
import CoreNetworking
import Foundation

// MARK: - The domain model

/// What `CatalogView` renders. `Sendable`/`Equatable`, never the SwiftData `@Model` or the
/// network DTO directly (M2) — see `Services/CatalogService.swift` and
/// `Stores/CatalogStore.swift` for the two places that map into this.
public nonisolated struct Item: Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let title: String

    public init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }
}

// MARK: - Domain errors (M1)

/// Every way refreshing the catalog can fail — never `APIError`, which stops at the
/// `Logic`/`Service` boundary.
public enum CatalogError: DomainError, Equatable {
    case offline
    case server
    case unknown

    // A refresh failure is always worth retrying (pull-to-refresh, a reload button):
    // unlike LoginApp's `.invalidCredentials` there is no "this will never succeed"
    // outcome here — every case is a transient network condition.
    public var isRetryable: Bool { true }

    public var screenError: ScreenError {
        switch self {
        case .offline:
            return ScreenError(title: "No connection", message: "Check your network and try again.")
        case .server:
            return ScreenError(title: "Server error", message: "Please try again later.")
        case .unknown:
            return ScreenError(title: "Something went wrong", message: "Please try again.")
        }
    }
}

// MARK: - Logic

/// The cache-then-network contract (`ARQUITECTURA-KIT-2026-09-02.md` §8, M7), exposed as
/// two explicit calls rather than an `AsyncStream` — simpler to call and to test.
/// `CatalogViewModel` sequences them: show `cached()` immediately (if any), then call
/// `refresh()`; a `refresh()` failure is a banner when `cached()` returned something, or
/// the screen's error phase when it didn't. That policy lives in the `ViewModel` — this
/// protocol only describes WHAT each call does, not how a caller reacts to failure.
public protocol CatalogLogicProtocol: Logic {
    /// Whatever is currently persisted locally, or `[]` if there is nothing (or reading it
    /// failed) — never throws, there is no "wrong" answer for "what do we have cached".
    func cached() async -> [Item]

    /// Fetches the catalog from the network, persists it, and returns it. Throws
    /// `CatalogError` (M1) on failure; the previously cached items are left untouched.
    func refresh() async throws -> [Item]
}

/// ALL of the feature's business logic: coordinates `CatalogServicing` (network) and
/// `CatalogStoring` (local cache), and maps any service failure to `CatalogError`.
///
/// `nonisolated` (M5): not tied to the main actor.
public nonisolated final class CatalogLogic: CatalogLogicProtocol {
    private let catalogService: any CatalogServicing
    private let catalogStore: any CatalogStoring

    /// - Parameters:
    ///   - catalogService: The one API call this feature makes. Injected as a protocol.
    ///   - catalogStore: Local cache. Injected as a protocol — never the concrete
    ///     `SwiftDataCatalogStore`/`InMemoryCatalogStore`
    ///     (`ARQUITECTURA-KIT-2026-09-02.md` §1, rule 3).
    public init(catalogService: any CatalogServicing, catalogStore: any CatalogStoring) {
        self.catalogService = catalogService
        self.catalogStore = catalogStore
    }

    public func cached() async -> [Item] {
        (try? await catalogStore.fetchAll()) ?? []
    }

    public func refresh() async throws -> [Item] {
        do {
            let items = try await catalogService.fetchItems()
            // Best-effort: the fresh items are still returned even if persisting them
            // fails — a cache write failure shouldn't turn a successful network refresh
            // into an error.
            try? await catalogStore.replaceAll(items)
            return items
        } catch {
            // `catalogService.fetchItems` is `throws(APIError)` (typed throws): `error`
            // here is already `APIError`, not `any Error`.
            throw Self.mapError(error)
        }
    }

    private static func mapError(_ error: APIError) -> CatalogError {
        switch error.category {
        case .offline:
            return .offline
        case .server:
            return .server
        default:
            return .unknown
        }
    }
}
