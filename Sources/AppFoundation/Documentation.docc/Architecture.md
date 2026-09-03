# Arquitectura

View → ViewModel → Logic → Services/Stores: la forma que sigue cualquier feature
construido sobre AppFoundation, en sus cuatro variantes.

## Overview

Un `Logic` por `ViewModel`. Todo entra por `init`, siempre como protocolo. Nada llama a
`Container.shared`/`@Inject` por su cuenta — el composition root es el `XxxModule`.

```
Features/Login/
├── LoginView.swift            SwiftUI. Solo conoce al ViewModel vía ScreenContainer(vm) { send in … }.
├── LoginViewModel.swift       LogicViewModel<any LoginLogicProtocol>, ActionHandling.
│                              init(logic:). NO conoce services, stores ni red.
├── LoginLogic.swift           LoginLogicProtocol + LoginLogic. Toda la lógica de negocio.
│                              init(loginService:sessionStore:). Sin SwiftUI.
├── Services/LoginService.swift    LoginServicing + LoginService(api:). Una llamada a API = un Service.
├── Stores/SessionStore.swift      SessionStoring + implementación local. Persistencia local = un Store.
└── Tests/
    ├── LoginViewModelTests.swift   VM con LoginLogicMock (spy).
    ├── LoginLogicTests.swift       Logic con LoginServiceMock + SessionStoreMock.
    ├── LoginServiceTests.swift     Service con MockAPIService / InMemoryTransport.
    └── Mocks/                      Un mock/spy por protocolo.
```

### Las reglas

1. **ViewModel** no importa CoreNetworking ni referencia `APIService`/`URLSession`/
   `*Service`/`*Store`; solo `*LogicProtocol` por `init`. Conforma `ActionHandling`.
2. **Logic** no importa SwiftUI/UIKit, no referencia `*ViewModel`; declara `*LogicProtocol`
   y su implementación; dependencias por `init` como protocolos.
3. **Service** declara `*Servicing` + implementación; solo él toca
   `APIServiceProtocol`/`BaseRequest`. **Store** declara `*Storing` + implementación; solo
   él toca SwiftData/CoreData/UserDefaults/Keychain/FileManager. Un `actor` que recibe por
   `init` un valor no-`Sendable` (`UserDefaults`, `FileManager`, un cliente de Keychain) y
   conforma inline a su `*Storing: Sendable` no compila bajo `defaultIsolation(MainActor)`
   — declara la conformidad en una `extension` (o inyecta un valor `Sendable`):

   ```swift
   actor UserDefaultsSettingsStore {
       private let defaults: UserDefaults
       init(defaults: UserDefaults = .standard) { self.defaults = defaults }   // compila
   }
   extension UserDefaultsSettingsStore: SettingsStoring {}
   ```

   Repro completo y todas las variantes probadas en `docs/repros/actor-inline-conformance.md`;
   ejemplo real en `Examples/NotesApp/Sources/NotesApp/Features/Notes/Stores/NotesSettingsStore.swift`.
4. **View** no referencia `*Logic`/`*Service`/`*Store`/`APIService`; recibe el ViewModel y
   usa `ActionSender`.
5. Cada `XxxViewModel.swift` tiene su `XxxLogic.swift`.
6. Ninguna clase concreta de Service/Store/Logic aparece en un `init` de otra capa: siempre
   `any XxxProtocol`.

`ArchitectureLint` (<doc:Lint>) hace fallar el build si alguna se rompe.

### Las cuatro variantes

| Variante | Logic depende de | Ejemplo |
|---|---|---|
| Solo API | `any XxxServicing` | `Examples/LoginApp` |
| Solo local | `any XxxStoring` | `Examples/NotesApp` (SwiftData) |
| API + local | ambos (`cached()` + `refresh()`, cache-then-network) | `Examples/CatalogApp` |
| Sin datos | nada (o un `Clock`, una regla pura) | `Examples/CounterApp` |

`Logic` (`public protocol Logic: AnyObject {}`) es el marcador que toda `XxxLogicProtocol`
conforma — sin requisitos propios, documenta la arquitectura en el tipo y permite al
linter/generador reconocerla.

### Variante API + local: cache-then-network

`CatalogLogic` expone dos llamadas, nunca un `AsyncStream` — más simple de llamar y de
testear: `cached()` (nunca lanza, `[]` si no hay nada) y `refresh()` (lanza en error). El
ViewModel secuencia las dos y decide la política: caché presente + `refresh()` falla →
banner, contenido intacto; caché vacía + `refresh()` falla → fase de error de la pantalla.

<!-- snippet: architecture-cache-then-network -->
```swift
import AppFoundation

struct Item: Sendable, Equatable {
    let id: String
    let title: String
}

enum CatalogError: DomainError {
    case offline

    var screenError: ScreenError {
        ScreenError(title: "Sin conexión", message: "Mostrando la última copia guardada.")
    }
}

protocol CatalogServicing: Sendable {
    func fetchItems() async throws -> [Item]
}

protocol CatalogStoring: Sendable {
    func cachedItems() async -> [Item]
    func replaceAll(_ items: [Item]) async
}

protocol CatalogLogicProtocol: Logic, Sendable {
    func cached() async -> [Item]
    func refresh() async throws(CatalogError) -> [Item]
}

final class CatalogLogic: CatalogLogicProtocol {
    private let service: any CatalogServicing
    private let store: any CatalogStoring

    init(service: any CatalogServicing, store: any CatalogStoring) {
        self.service = service
        self.store = store
    }

    func cached() async -> [Item] {
        await store.cachedItems()
    }

    func refresh() async throws(CatalogError) -> [Item] {
        do {
            let items = try await service.fetchItems()
            await store.replaceAll(items)
            return items
        } catch {
            throw .offline
        }
    }
}

final class CatalogViewModel: LogicViewModel<any CatalogLogicProtocol>, ActionHandling {
    private(set) var items: [Item] = []

    enum Action: Sendable { case load }

    func handle(_ action: Action) {
        switch action {
        case .load: load()
        }
    }

    private func load() {
        performLoad(successTransition: .preserveCurrentPhase) { vm in
            let cached = await vm.logic.cached()
            if !cached.isEmpty {
                vm.items = cached
                vm.setContent()
            }

            do {
                vm.items = try await vm.logic.refresh()
                vm.setContent()
            } catch {
                // Sin caché que mostrar: es el fallo de la pantalla — deja que el
                // catch de performLoad lo convierta en fase de error.
                guard !cached.isEmpty else { throw error }
                // Hay caché: el fallo del refresh no se lleva el contenido, es un banner (M7).
                vm.handleActivityError(error, strategy: .banner)
            }
        }
    }
}
```

## Mejoras sobre la arquitectura base

Cada una cierra un hueco concreto. Se aplican en los cuatro ejemplos, en las plantillas del
generador y en el linter.

| # | Mejora | Qué evita | Quién lo hace cumplir |
|---|---|---|---|
| M1 | **Errores de dominio entre capas.** Un Service lanza `APIError`; la Logic lo traduce a un error de dominio del feature (`DomainError`) antes de devolverlo. | Que el copy de error dependa de la red en la capa de UI. | `ArchitectureLint` R7. |
| M2 | **Modelos por capa.** DTOs viven en el Service/Store; se mapean a modelos de dominio antes de salir. | Que un cambio en el JSON toque Logic o View. | R8. |
| M3 | **Navegación solo desde el ViewModel.** La Logic no conoce `Router`/`Coordinator`. | Mezclar orquestación con negocio. | R9. |
| M4 | **Composition root único.** Cada feature tiene su `XxxModule: DependencyModule`. | `Container.shared` llamado desde cualquier capa. | R10. |
| M5 | **Aislamiento por capa.** ViewModel `@MainActor`; Logic `nonisolated`, `async`; Service `struct Sendable`; Store `actor`/`@ModelActor`. | Estado compartido implícito. | Plantillas; R11 (aviso). |
| M6 | **Estado transversal como Store.** Sesión, feature flags: un `SessionStore` inyectado, nunca un singleton global. Logout global al 401 vía `SessionExpiring`. | Un `NotificationCenter` global para sesión. | `Examples/LoginApp`; <doc:Recipes>. |
| M7 | **Cache-then-network fijado.** `cached()` + `refresh()`, dos llamadas explícitas. | Que cada app invente su política. | `Examples/CatalogApp`. |
| M8 | **Feature como módulo (opt-in).** `--module` separa `XxxCore`/`XxxUI` en targets locales — la dirección de dependencias queda impuesta por el compilador. | Necesitar el linter para apps grandes. | <doc:Generator>. |
| M9 | **Previews y spies generados.** Cada View generada trae `#Preview`; cada protocolo, su mock con contadores. | Escribir un mock a mano cada vez. | <doc:Generator>. |
| M10 | **Observabilidad de negocio.** Un tracker inyectado en la Logic, nunca en la View/ViewModel. | Que la analítica se cuele en la capa de UI. | Plantilla `--analytics`. |

## Topics

### El kit

- ``Logic``
- ``LogicViewModel``
- ``DomainError``

### Ver también

- <doc:GettingStarted>
- <doc:Generator>
- <doc:Lint>
- <doc:Recipes>
