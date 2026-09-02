// Un deep link que reemplaza toda la pila: `coordinator.handle(url:as:)` parsea la
// URL y traduce a una `DeepLinkAction` — sin if/else repartido por la app.
import AppFoundation
import Foundation

enum AppRoute: Hashable {
    case home
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
func handleIncomingURL(_ url: URL, coordinator: Coordinator<AppRoute>) {
    coordinator.handle(url, as: AppDeepLink.self) { link in
        switch link {
        case .profile(let id):
            return .setStack([.profile, .profileDetails(id: id)])
        }
    }
}
