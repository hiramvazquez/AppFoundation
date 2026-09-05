import Foundation
import Testing

@testable import AppFoundation

// MARK: - Fase 3.6: deep links conectados (A12)

nonisolated enum TestDeepLink: DeepLinkType, Equatable {
    case notifications
    case profile(userId: String)

    static func parse(_ url: URL) -> TestDeepLink? {
        let components = url.pathComponents
        if components.contains("notifications") { return .notifications }
        if let index = components.firstIndex(of: "profile"), components.count > index + 1 {
            return .profile(userId: components[index + 1])
        }
        return nil
    }
}

@Suite("Deep links → Coordinator")
struct DeepLinkTests {
    enum TestRoute: Hashable {
        case home, notifications, settings, login
        case profile(userId: String)
    }

    let coordinator = Coordinator<TestRoute>(root: .home)

    private func map(_ link: TestDeepLink) -> DeepLinkAction<TestRoute>? {
        switch link {
        case .notifications: return .setStack([.notifications])
        case .profile(let id): return .push(.profile(userId: id))
        }
    }

    @Test func parseableURLAppliesSetStack() throws {
        let url = try #require(URL(string: "myapp://open/notifications"))
        let handled = coordinator.handle(url, as: TestDeepLink.self, map: map)

        #expect(handled)
        #expect(coordinator.mainStack.path == [.notifications])
    }

    @Test func parseableURLAppliesPushWithPayload() throws {
        let url = try #require(URL(string: "https://example.com/profile/42"))
        let handled = coordinator.handle(url, as: TestDeepLink.self, map: map)

        #expect(handled)
        #expect(coordinator.mainStack.path == [.profile(userId: "42")])
    }

    @Test func unparseableURLIsIgnored() throws {
        coordinator.push(.settings)
        let url = try #require(URL(string: "myapp://open/unknown"))

        let handled = coordinator.handle(url, as: TestDeepLink.self, map: map)

        #expect(!handled)
        #expect(coordinator.mainStack.path == [.settings])
    }

    @Test func mapReturningNilIgnoresTheLink() throws {
        let url = try #require(URL(string: "myapp://open/notifications"))
        let handled = coordinator.handle(url, as: TestDeepLink.self) { _ in nil }

        #expect(!handled)
        #expect(coordinator.mainStack.path.isEmpty)
    }

    /// setStack de un deep link es dueño del estado resultante: el modal se descarta.
    @Test func setStackActionDismissesModal() {
        coordinator.present(.settings, as: .sheet)

        coordinator.handle(.setStack([.notifications]))

        #expect(coordinator.modal == nil)
        #expect(coordinator.mainStack.path == [.notifications])
    }

    /// push de un deep link respeta la capa activa (va al modal si hay uno).
    @Test func pushActionTargetsActiveLayer() {
        coordinator.present(.settings, as: .sheet)

        coordinator.handle(.push(.profile(userId: "7")))

        #expect(coordinator.modal?.stack.path == [.profile(userId: "7")])
        #expect(coordinator.mainStack.path.isEmpty)
    }

    @Test func presentActionPresentsModally() {
        coordinator.handle(.present(.settings, style: .fullScreenCover))
        #expect(coordinator.isFullScreenPresented)
        #expect(coordinator.fullScreenStack?.root == .settings)
    }

    // MARK: - HALLAZGO 2: patrón documentado — `map` valida sesión antes de navegar

    /// El patrón que documenta `Coordinator.handle(_:as:map:)`: una ruta que asume sesión
    /// iniciada se comprueba DENTRO de `map`, antes de devolver la acción — nunca se confía
    /// en que la vista destino compruebe la sesión por su cuenta.
    private func mapRequiringSession(isAuthenticated: Bool) -> (TestDeepLink) -> DeepLinkAction<TestRoute>? {
        { link in
            switch link {
            case .notifications:
                return .setStack([.notifications])
            case .profile(let id):
                guard isAuthenticated else {
                    // Sin sesión: nunca se devuelve la ruta protegida, ni siquiera para
                    // ignorarla en silencio — se redirige a login. `nil` también sería
                    // válido si la app prefiere ignorar el enlace en vez de redirigir.
                    return .setStack([.login])
                }
                return .push(.profile(userId: id))
            }
        }
    }

    @Test func mapRedirectsToLoginInsteadOfProtectedRouteWhenNotAuthenticated() throws {
        let url = try #require(URL(string: "https://example.com/profile/42"))

        let handled = coordinator.handle(url, as: TestDeepLink.self, map: mapRequiringSession(isAuthenticated: false))

        #expect(handled)
        #expect(coordinator.mainStack.path == [.login])
        #expect(coordinator.mainStack.path != [.profile(userId: "42")])
    }

    @Test func mapAppliesProtectedRouteWhenAuthenticated() throws {
        let url = try #require(URL(string: "https://example.com/profile/42"))

        let handled = coordinator.handle(url, as: TestDeepLink.self, map: mapRequiringSession(isAuthenticated: true))

        #expect(handled)
        #expect(coordinator.mainStack.path == [.profile(userId: "42")])
    }

    /// Un enlace sin gate (rutas que no requieren sesión) sigue funcionando igual: la
    /// comprobación solo se añade donde la ruta lo necesita, no globalmente.
    @Test func mapWithoutSessionRequirementIsUnaffectedByTheGuard() throws {
        let url = try #require(URL(string: "myapp://open/notifications"))

        let handled = coordinator.handle(url, as: TestDeepLink.self, map: mapRequiringSession(isAuthenticated: false))

        #expect(handled)
        #expect(coordinator.mainStack.path == [.notifications])
    }
}
