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

### Seguridad: la `URL` es entrada no confiable

`url` llega de fuera de tu proceso — un universal link, un esquema propio, una notificación
push, otra app abriendo la tuya. El paquete no tiene (ni puede tener) un sistema de permisos:
solo la app conoce cuáles de sus rutas requieren sesión iniciada. El cierre `map` que le pasas
a `handle(url:as:map:)` es el ÚNICO sitio para vetar o redirigir un enlace antes de que llegue
a tocar el estado de navegación — valida ahí, no en la vista destino:

- **Comprueba la sesión ANTES de devolver una acción**, nunca después. Si la ruta que vas a
  devolver asume un usuario autenticado, compruébalo primero; si no hay sesión, devuelve `nil`
  para ignorar el enlace o redirige a una ruta segura (p. ej. `.setStack([.login])`) — nunca
  confíes en que la pantalla destino compruebe la sesión por ti.
- **Trata cualquier parámetro que `parse` extraiga de la URL como no confiable** (un id, un
  token, un query string): valídalo en `map` antes de que forme parte de una `Route`.
- `.setStack` es la acción más destructiva: descarta cualquier modal presentado y reemplaza
  toda la pila. Un enlace mapeado sin la comprobación de sesión puede saltarse login u
  onboarding por completo.

El paquete no ofrece un hook de "veto" aparte de `map` a propósito: `map` ya se ejecuta de
forma síncrona con captura completa del cierre, así que ya puede leer el estado de
sesión/autenticación que tu app inyecte y rechazar o reescribir la acción — un parámetro
adicional solo envolvería el `guard` de abajo en ceremonia, sin añadir nada que `map` no
pudiera hacer ya.

<!-- snippet: navigation-deeplink -->
```swift
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
```

```swift
.onOpenURL { url in
    handleIncomingURL(url, coordinator: coordinator, isAuthenticated: { session.isAuthenticated })
}
```

`.setStack` descarta cualquier modal presentado antes de reemplazar la pila principal —
"abre la app exactamente aquí" es dueño del estado de navegación resultante. Por eso el
mapeo de arriba solo devuelve `.setStack([.profile, ...])` cuando ya comprobó la sesión.

## Topics

### Núcleo

- ``Router``
- ``Coordinator``
- ``CoordinatorView``

### Deep links

- ``DeepLinkType``
- ``DeepLinkAction``
