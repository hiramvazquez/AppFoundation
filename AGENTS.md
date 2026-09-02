# AppFoundation — guía para agentes

Arquitectura obligatoria de cualquier feature: **View → ViewModel → Logic → Services/Stores**.
Un `Logic` por `ViewModel`. Todo entra por `init`, siempre como protocolo. Nada de esto
llama a `Container.shared`/`@Inject` por su cuenta: el composition root es el `XxxModule`.

## Capas

- **View** (SwiftUI): recibe el `ViewModel`, renderiza con `ScreenContainer(vm) { send in … }`.
  Nunca importa `CoreNetworking`, nunca referencia `*Logic`/`*Service`/`*Store`.
- **ViewModel** (`@MainActor`): `final class XxxViewModel: LogicViewModel<any XxxLogicProtocol>,
  ActionHandling`. Orquesta: recibe `Action` en `handle(_:)`, llama a `logic`, actualiza
  `phase`/estado propio, decide navegación (`Router`/`Coordinator`). Nunca conoce
  `APIService`, `URLSession`, SwiftData ni un `*Service`/`*Store` concreto — solo `logic`.
- **Logic** (`nonisolated`, métodos `async`): `protocol XxxLogicProtocol: Logic { … }` +
  `final class XxxLogic: XxxLogicProtocol`. TODA la lógica de negocio; traduce el error del
  Service/Store (`APIError`, SwiftData) a un error de dominio propio (`XxxError: DomainError`)
  ANTES de devolverlo — el ViewModel y el `ErrorPresenting` nunca ven `APIError`. Sin
  `import SwiftUI`/`UIKit`. Sin referencias a `*ViewModel`/`Router`/`Coordinator`.
  Dependencias por `init` como `any XxxServicing`/`any XxxStoring`.
- **Service** (API, `struct Sendable`): `protocol XxxServicing: Sendable` + una
  implementación que es la ÚNICA que toca `APIServiceProtocol`/`BaseRequest` y que devuelve
  MODELOS DE DOMINIO (nunca el DTO/`Response` decodificado). Un Service = una llamada a API
  con su propio `BaseRequest`. Conformar `EndpointService` (`CoreNetworking`) da `call(_:)`
  gratis.
- **Store** (local, `actor`/`@ModelActor` con SwiftData): `protocol XxxStoring` + una
  implementación que es la ÚNICA que toca SwiftData/CoreData/UserDefaults/Keychain/
  FileManager, y que igualmente devuelve modelos de dominio. Misma forma que un Service,
  distinto origen.

## Las cuatro variantes (mismas reglas)

| Variante | `Logic` depende de | Ejemplo |
|---|---|---|
| Solo API | `any XxxServicing` | `Examples/LoginApp` (+ `SessionStore`, logout global) |
| Solo local | `any XxxStoring` | `Examples/NotesApp` (SwiftData) |
| API + local | ambos (`cached()` + `refresh()`, cache-then-network) | `Examples/CatalogApp` |
| Sin datos | nada | `Examples/CounterApp` |

## Piezas de este paquete

- `Logic` (`Architecture/Logic/Logic.swift`): marcador `protocol Logic: AnyObject {}`.
- `DomainError` (`Architecture/AppError/DomainError.swift`): `protocol DomainError: Error,
  AppErrorConvertible, Sendable { var isRetryable: Bool { get } }` (default `false`) — lo
  que un `Logic` lanza en vez de propagar el error de su Service/Store.
- `LogicViewModel<L>` (`Architecture/ViewModels/LogicViewModel.swift`): `open class
  LogicViewModel<L>: BaseViewModel` con `public let logic: L`. NO conforma `ActionHandling`
  — cada subclase declara su propio `enum Action` y `handle(_:)`.
- `AppFoundationTestSupport` (producto SEPARADO, nunca en el binario de producción):
  `InMemoryStore<Key, Value>` (actor genérico para dobles de `*Storing`), `ManualClock`,
  `SpyRecorder<Call>`.

## Cómo testear cada capa

- **ViewModel**: `XxxLogicMock: XxxLogicProtocol` (spy) → `viewModel.handle(.acción)` →
  `await viewModel.inFlightLoad?.value` → assert sobre `phase`/propiedades observables.
- **Logic**: `XxxServiceMock`/`XxxStoreMock` (o `InMemoryStore`) → llama al método del
  `Logic` directamente; incluye un test por cada mapeo de error a `DomainError`.
- **Service**: `MockAPIService` (stub por tipo de request) para el caso feliz/error, e
  `InMemoryTransport` para el pipeline real (retries, interceptores, refresh de token).
- **Store**: `InMemoryStore`/`InMemoryXxxStore` en tests; SwiftData con `ModelContainer`
  en memoria (`isStoredInMemoryOnly: true`) solo en el test del Store real.

## Qué NO hacer

- No inyectes un tipo concreto de Service/Store/Logic en otra capa — siempre `any XxxProtocol`.
- No dejes que `APIError`/un error de SwiftData llegue al ViewModel: mapéalo a `DomainError`
  dentro del `Logic`.
- No pongas lógica de negocio ni navegación en el `ViewModel`/`Logic` respectivamente.
- No llames a `Container.shared`/`@Inject` desde ViewModel/Logic/Service/Store: regístralos
  y resuélvelos desde el `XxxModule` (composition root).

Ver también: [Examples/](Examples/) (los cuatro ejemplos de variante, código de referencia)
y `README.md` (instalación y resto de piezas del paquete).
