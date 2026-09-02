# AppFoundation — guía para agentes

Arquitectura obligatoria de cualquier feature: **View → ViewModel → Logic → Services/Stores**.
Un `Logic` por `ViewModel`. Todo entra por `init`, siempre como protocolo.

## Capas

- **View** (SwiftUI): recibe el `ViewModel`, renderiza con `ScreenContainer(vm) { send in … }`.
  Nunca importa `CoreNetworking`, nunca referencia `*Logic`/`*Service`/`*Store`.
- **ViewModel**: `final class XxxViewModel: LogicViewModel<any XxxLogicProtocol>, ActionHandling`.
  Orquesta: recibe `Action` en `handle(_:)`, llama a `logic`, actualiza `phase`/estado propio.
  Nunca conoce `APIService`, `URLSession`, SwiftData ni un `*Service`/`*Store` concreto —
  solo `logic`.
- **Logic**: `protocol XxxLogicProtocol: Logic { … }` + `final class XxxLogic: XxxLogicProtocol`.
  TODA la lógica de negocio. Sin `import SwiftUI`/`UIKit`. Sin referencias a `*ViewModel`.
  Dependencias por `init` como `any XxxServicing`/`any XxxStoring`.
- **Service** (API): `protocol XxxServicing: Sendable` + una implementación que es la
  ÚNICA que toca `APIServiceProtocol`/`BaseRequest`. Un Service = una llamada a API con su
  propio `BaseRequest`. Conformar `EndpointService` (`CoreNetworking`) da `call(_:)` gratis.
- **Store** (local): `protocol XxxStoring` + una implementación que es la ÚNICA que toca
  SwiftData/CoreData/UserDefaults/Keychain/FileManager. Misma forma que un Service, distinto
  origen.

## Las cuatro variantes (mismas reglas)

| Variante | `Logic` depende de | Ejemplo |
|---|---|---|
| Solo API | `any XxxServicing` | `Examples/LoginApp` |
| Solo local | `any XxxStoring` | `Examples/NotesApp` |
| API + local | ambos (cache-then-network) | `Examples/CatalogApp` |
| Sin datos | nada | `Examples/CounterApp` |

## Piezas de este paquete

- `Logic` (`Architecture/Logic/Logic.swift`): marcador `protocol Logic: AnyObject {}` que
  toda `XxxLogicProtocol` extiende. Sin requisitos: documenta intención para humanos,
  agentes y el futuro linter/generador (PRD-AF-08).
- `LogicViewModel<L>` (`Architecture/ViewModels/LogicViewModel.swift`): `open class
  LogicViewModel<L>: BaseViewModel` con `public let logic: L`. Hereda `phase`/`activity`/
  `performLoad`/`performActivity` de `BaseViewModel`. NO conforma `ActionHandling` — cada
  subclase declara su propio `enum Action` y `handle(_:)`.
- `AppFoundationTestSupport` (producto SEPARADO, nunca en el binario de producción):
  `InMemoryStore<Key, Value>` (actor genérico para dobles de `*Storing`), `ManualClock`
  (reloj determinista para tests), `SpyRecorder<Call>` (grabador de llamadas para spies).

## Cómo testear cada capa

- **ViewModel**: `XxxLogicMock: XxxLogicProtocol` (spy, con `SpyRecorder`/contadores) →
  `viewModel.handle(.acción)` → `await viewModel.inFlightLoad?.value` → assert sobre
  `phase`/propiedades observables. Nunca llames al método `private` directamente.
- **Logic**: `XxxServiceMock`/`XxxStoreMock` (o `InMemoryStore`) → llama al método del
  `Logic` directamente (sin SwiftUI, sin ViewModel).
- **Service**: `MockAPIService` (stub por tipo de request) para el caso feliz/error, e
  `InMemoryTransport` para el pipeline real (retries, interceptores, refresh de token).
- **Store**: `InMemoryStore`/`InMemoryXxxStore` en tests; SwiftData con `ModelContainer`
  en memoria (`isStoredInMemoryOnly: true`) solo en el test del Store real.

## Qué NO hacer

- No inyectes un `APIService`, `URLSession` ni un `*Service`/`*Store` concreto en un
  `ViewModel` o en el `init` de otro `Logic`/`Service`/`Store` — siempre `any XxxProtocol`.
- No pongas lógica de negocio en el `ViewModel`: si decide algo más que "qué `Action` llama
  a qué método de `logic`", pertenece al `Logic`.
- No importes SwiftUI/UIKit en un `Logic`.
- No construyas el `Logic` de un `ViewModel` con un tipo concreto codificado a mano en
  producción sin pasar por `init(logic:)` — igual en tests: pasa el mock ahí, no mutando
  propiedades después de construir.

Ver también: [Examples/](Examples/) (los cuatro ejemplos de variante, código de referencia)
y `README.md` (instalación y resto de piezas del paquete).
