# Navegación

`Router`, `Coordinator`, `CoordinatorView` y los deep links: una pila por
`NavigationStack`, una sola capa modal.

## Overview

`Coordinator<Route: Hashable>` modela **una pila** más **una capa modal**: presentar
mientras un modal está visible reemplaza al anterior (política documentada). Un
`ViewModel` depende de `Router<Route>` (el protocolo), no del `Coordinator` concreto,
siempre que sea posible.

```swift
enum AppRoute: Hashable {
    case home
    case profile
    case profileDetails(id: String)
}

@State private var coordinator = Coordinator<AppRoute>(root: .home)

var body: some View {
    CoordinatorView(coordinator: coordinator) { route in
        switch route {
        case .home: HomeView(viewModel: HomeViewModel(router: coordinator))
        case .profile: ProfileView(viewModel: ProfileViewModel(router: coordinator))
        case .profileDetails(let id): ProfileDetailsView(id: id)
        }
    }
}
```

¿Necesitas modal-sobre-modal? Dale al destino presentado su propio `Coordinator` +
`CoordinatorView` — no hay una segunda capa modal en el mismo coordinador.

## Deep links

`DeepLinkType.parse(_:)` traduce una `URL` a un caso propio; `coordinator.handle(url:as:)`
aplica la `DeepLinkAction` (`.setStack`, `.push`, `.present`) que tu mapeo produce:

<!-- snippet: navigation-deeplink -->
```swift
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
```

```swift
.onOpenURL { url in
    handleIncomingURL(url, coordinator: coordinator)
}
```

`.setStack` descarta cualquier modal presentado antes de reemplazar la pila principal —
"abre la app exactamente aquí" es dueño del estado de navegación resultante.

## Topics

### Núcleo

- ``Router``
- ``Coordinator``
- ``CoordinatorView``

### Deep links

- ``DeepLinkType``
- ``DeepLinkAction``
