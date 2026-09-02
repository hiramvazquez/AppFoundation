import Foundation

/// Local persistence for the current session's bearer token — the only piece of state
/// this app treats as transversal (`ARQUITECTURA-KIT-2026-09-02.md` §8, M6): `LoginLogic`
/// writes it on a successful login, `LoginService.swift`'s `BearerTokenInterceptor` reads
/// it on every outgoing request, and its own `TokenRefreshRetrier` overwrites it on a
/// silent 401 → refresh → retry.
///
/// A real app persists this in Keychain instead of memory; the protocol is the same
/// shape either way — only this file (and `InMemorySessionStore`/the eventual Keychain
/// implementation) ever touches the concrete storage.
public protocol SessionStoring: Sendable {
    /// The current bearer token, or `nil` when signed out.
    func currentToken() async -> String?

    /// Persists `token` as the current session.
    func save(_ token: String) async

    /// Clears the current session (sign-out, or a refresh that could not recover it).
    func invalidate() async
}

/// The `SessionStoring` this app runs with. `actor`, not a lock-guarded class (M5): the
/// token is read from `BearerTokenInterceptor` and written from `LoginLogic`/the refresh
/// retrier concurrently, which is the exact case an actor exists for.
public actor SessionStore: SessionStoring {
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func currentToken() async -> String? { token }

    public func save(_ token: String) async {
        self.token = token
    }

    public func invalidate() async {
        token = nil
    }
}
