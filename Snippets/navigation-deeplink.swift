// Un deep link que reemplaza toda la pila: `coordinator.handle(url:as:)` parsea la
// URL y traduce a una `DeepLinkAction` — sin if/else repartido por la app. `map` es el
// único sitio donde la app puede vetar una ruta que asume sesión iniciada: la URL viene
// de fuera del proceso (universal link, notificación, otra app), así que la sesión se
// comprueba AQUÍ, antes de devolver la acción — nunca dentro de la vista destino.
import AppFoundation
import Foundation

enum AppRoute: Hashable {
    case home
    case login
    case profile
    case profileDetails(id: String)
}

enum AppDeepLink: DeepLinkType {
    case profile(id: String)

    static func parse(_ url: URL) -> AppDeepLink? {
        let components = url.pathComponents
        guard let index = components.firstIndex(of: "profile"), components.count > index + 1 else {
            return nil
        }
        return .profile(id: components[index + 1])
    }
}

@MainActor
func handleIncomingURL(_ url: URL, coordinator: Coordinator<AppRoute>, isAuthenticated: () -> Bool) {
    coordinator.handle(url, as: AppDeepLink.self) { link in
        switch link {
        case .profile(let id):
            // `.profile`/`.profileDetails` requieren sesión: sin esta comprobación, un
            // deep link malicioso o mal dirigido saltaría login/onboarding directamente.
            guard isAuthenticated() else {
                return .setStack([.login])
            }
            return .setStack([.profile, .profileDetails(id: id)])
        }
    }
}
