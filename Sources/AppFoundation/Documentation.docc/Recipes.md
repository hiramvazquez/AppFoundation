# Recetas

Patrones completos, listos para copiar: paginación, pull-to-refresh, formularios y logout
global.

## Paginación

La carga inicial usa `performLoad`; cada página siguiente es `activity` — no reemplaza el
contenido ya visible mientras llega más.

<!-- snippet: recipe-pagination -->
```swift
import AppFoundation

struct Page: Sendable {
    let items: [String]
    let hasMore: Bool
}

protocol FeedLoading: Sendable {
    func load(page: Int) async throws -> Page
}

final class FeedViewModel: BaseViewModel, ActionHandling {
    private(set) var items: [String] = []
    private var currentPage = 0
    private var hasMore = true
    private let service: any FeedLoading

    enum Action: Sendable {
        case load
        case loadNextPage
    }

    init(service: any FeedLoading) {
        self.service = service
    }

    func handle(_ action: Action) {
        switch action {
        case .load: load()
        case .loadNextPage: loadNextPage()
        }
    }

    private func load() {
        performLoad { vm in
            let page = try await vm.service.load(page: 0)
            vm.items = page.items
            vm.hasMore = page.hasMore
            vm.currentPage = 0
        }
    }

    private func loadNextPage() {
        guard hasMore else { return }
        performActivity(style: .inline) { vm in
            let page = try await vm.service.load(page: vm.currentPage + 1)
            vm.items += page.items
            vm.hasMore = page.hasMore
            vm.currentPage += 1
        }
    }
}
```

## Pull-to-refresh

`.refreshable` de SwiftUI espera un closure `async`: encaja directo con la variante
estructurada `activity(_:)`. Un fallo se convierte en banner (comportamiento por defecto
de `activity`/`performActivity`), el contenido se queda visible.

<!-- snippet: recipe-pull-to-refresh -->
```swift
import AppFoundation
import SwiftUI

protocol ItemsLoading: Sendable {
    func fetch() async throws -> [String]
}

final class ItemsViewModel: BaseViewModel, ActionHandling {
    private(set) var items: [String] = []
    private let service: any ItemsLoading

    enum Action: Sendable {
        case load
    }

    init(service: any ItemsLoading) {
        self.service = service
    }

    func handle(_ action: Action) {
        switch action {
        case .load: load()
        }
    }

    private func load() {
        performLoad { vm in vm.items = try await vm.service.fetch() }
    }

    func refresh() async {
        await activity { vm in
            vm.items = try await vm.service.fetch()
        }
    }
}

struct ItemsView: View {
    @State private var viewModel: ItemsViewModel

    init(viewModel: ItemsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScreenContainer(viewModel) { send in
            List(viewModel.items, id: \.self) { Text($0) }
                .refreshable { await viewModel.refresh() }
                .task { send(.load) }
        }
    }
}
```

## Formulario con validación local

Valida antes de llamar a la Logic; el submit en sí va por `performActivity` — el
formulario es el contenido, se queda visible mientras se envía.

<!-- snippet: recipe-form -->
```swift
import AppFoundation

enum SignupError: DomainError {
    case invalidEmail

    var screenError: ScreenError {
        ScreenError(title: "Email inválido", message: "Revisa el formato del correo.")
    }
}

// `Sendable` explícito: sin `NonisolatedNonsendingByDefault` habilitado (como en este
// propio paquete, ver `AppFoundation/Package.swift`) un Logic nonisolated + async cruza
// de actor al llamarlo desde un ViewModel `@MainActor`.
protocol SignupLogicProtocol: Logic, Sendable {
    func signUp(email: String, password: String) async throws(SignupError)
}

final class SignupViewModel: LogicViewModel<any SignupLogicProtocol>, ActionHandling {
    var email = ""
    var password = ""

    enum Action: Sendable {
        case submit
    }

    func handle(_ action: Action) {
        switch action {
        case .submit: submit()
        }
    }

    private func submit() {
        guard email.contains("@") else {
            handleActivityError(SignupError.invalidEmail, strategy: .banner)
            return
        }
        performActivity { vm in
            try await vm.logic.signUp(email: vm.email, password: vm.password)
        }
    }
}
```

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
