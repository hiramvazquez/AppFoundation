import AppFoundation
import CoreNetworking
import Foundation

public nonisolated struct LoginItem: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
}

public enum LoginError: DomainError, Equatable {
    case offline
    case unknown

    public var isRetryable: Bool {
        switch self {
        case .offline: true
        case .unknown: false
        }
    }
}

public protocol LoginLogicProtocol: Logic {
    func load() async throws -> [LoginItem]
}

public nonisolated final class LoginLogic: LoginLogicProtocol {
    private let loginService: any LoginServicing
    private let loginStore: any LoginStoring

    public init(loginService: any LoginServicing, loginStore: any LoginStoring) {
        self.loginService = loginService
        self.loginStore = loginStore
    }

    public func load() async throws -> [LoginItem] {
        do {
            return try await loginService.fetchItems()
        } catch {
            throw Self.mapError(error)
        }
    }

    private static func mapError(_ error: APIError) -> LoginError {
        switch error.category {
        case .offline: return .offline
        default: return .unknown
        }
    }
}
