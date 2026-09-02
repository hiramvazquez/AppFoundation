# Recetas

Patrones completos, listos para copiar: paginación, pull-to-refresh, formularios y logout
global.

## Paginación

La carga inicial usa `performLoad`; cada página siguiente es `activity` — no reemplaza el
contenido ya visible mientras llega más.

@Snippet(path: "AppFoundation/Snippets/recipe-pagination")

## Pull-to-refresh

`.refreshable` de SwiftUI espera un closure `async`: encaja directo con la variante
estructurada `activity(_:)`. Un fallo se convierte en banner (comportamiento por defecto
de `activity`/`performActivity`), el contenido se queda visible.

@Snippet(path: "AppFoundation/Snippets/recipe-pull-to-refresh")

## Formulario con validación local

Valida antes de llamar a la Logic; el submit en sí va por `performActivity` — el
formulario es el contenido, se queda visible mientras se envía.

@Snippet(path: "AppFoundation/Snippets/recipe-form")

Para un campo de búsqueda que dispara una llamada por cada pulsación, combina esto con
`Debouncer` — ver <doc:Utilities>.

## Logout global al 401

Patrón M6 (<doc:Architecture>): la app implementa un `SessionExpiring` propio (no forma
parte del paquete — es un protocolo de la app, análogo a `*Storing`); un
`TokenRefreshRetrier` (CoreNetworking) que falla llama a `SessionStore.invalidate()` y
notifica esa sesión expirada; una vista raíz observa el estado de sesión y llama
`coordinator.setRoot(.login)`:

```swift
protocol SessionExpiring: Sendable {
    func sessionDidExpire() async
}

@Observable
final class AppSessionState: SessionExpiring {
    private(set) var isAuthenticated = true

    func sessionDidExpire() async {
        isAuthenticated = false
    }
}

struct RootView: View {
    let sessionState: AppSessionState
    let coordinator: Coordinator<AppRoute>

    var body: some View {
        CoordinatorView(coordinator: coordinator) { route in /* … */ }
            .onChange(of: sessionState.isAuthenticated) { _, isAuthenticated in
                if !isAuthenticated {
                    coordinator.setRoot(.login)
                }
            }
    }
}
```

El resto del mecanismo (`BearerTokenInterceptor`, `TokenRefreshRetrier`,
`TokenRefresher`) es de CoreNetworking — ver su receta de logout global, y
`AppFoundation/Examples/LoginApp` para el ejemplo completo end-to-end.

## Tests de cada capa

Ver <doc:Testing> para el patrón completo (spy de Logic, mocks de Service/Store,
`inFlightLoad`/`inFlightActivity` en vez de sondear).
