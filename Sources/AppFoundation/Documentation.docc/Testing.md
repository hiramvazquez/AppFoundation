# Testing

Un mock/spy por protocolo, `Swift Testing`, cero `Task.sleep` real.

## Overview

Cada capa se testea aislada de las demás, contra un doble de su única dependencia.

| Capa | Doble | Qué prueba |
|---|---|---|
| ViewModel | `XxxLogicMock` (spy) | `handle(.acción)` llama al método correcto de `logic`; `phase`/estado propio siguen el resultado |
| Logic | `XxxServiceMock`/`XxxStoreMock` (o `InMemoryStore`) | cada mapeo de error a `DomainError`; la regla de negocio en sí |
| Service | `MockAPIService` (CoreNetworking) | mapeo de request/response, caso feliz y error |
| Store | `InMemoryStore`/`InMemoryXxxStore` en tests unitarios; SwiftData con `ModelContainer` en memoria solo en el test del Store real |

### `AppFoundationTestSupport`

Producto separado — nunca en el binario de producción, nunca dependencia del producto
`AppFoundation`. Sus tipos viven en su propio módulo (`import AppFoundationTestSupport`),
fuera de este catálogo de documentación:

- `InMemoryStore<Key, Value>` — actor genérico para dobles de `*Storing`: sustituye a un
  `XxxStoreMock` escrito a mano cuando el Store real es solo un diccionario con forma de
  actor.
- `ManualClock` — mismo contrato que el de `CoreNetworkingTestSupport` (duplicado:
  AppFoundation no depende de CoreNetworking). Avanza el tiempo a mano, sin dormir de
  verdad.
- `SpyRecorder<Call>` — grabador de llamadas thread-safe para spies generados o hechos a
  mano.

### Tests deterministas del ViewModel: nunca sondear `phase`

`handle(_:)` devuelve `Void` — es el único punto de entrada de `ActionHandling`. En vez de sondear
`phase`/`hasError` en un bucle con `Task.sleep`, espera el `Task` que el view model ya
está corriendo:

```swift
@Test func loadShowsContent() async {
    let viewModel = ProfileViewModel(logic: LogicMock())

    viewModel.handle(.load)
    await viewModel.inFlightLoad?.value

    #expect(viewModel.phase == .content)
}
```

`inFlightLoad` cubre `performLoad`/`load(_:)`; `inFlightActivity` cubre
`performActivity`/`activity(_:)` — incluida una reintentada (`retry` vuelve a llamar
`performLoad`, así que `inFlightLoad` recoge el `Task` nuevo).

Cuando el test llama `performLoad`/`performActivity` directamente (no a través de
`handle(_:)`), ambos devuelven su propio `Task` — espera ese, sin necesidad de
`inFlightLoad`:

```swift
await viewModel.performLoad { vm in try await vm.repository.fetch() }.value
#expect(viewModel.phase == .content)
```

### Reloj y cancelación inyectados por instancia

Los tests que necesitan controlar el tiempo (banners con auto-dismiss) o la detección de
cancelación inyectan por `init`, nunca mutan `BaseViewModel.clock`/
`.cancellationRecognizer` (los `static var`, pensados para configuración a nivel de app):
un estático mutado por un test es visible desde cualquier otra suite corriendo en paralelo.

```swift
let viewModel = ProfileViewModel(logic: LogicMock(), clock: ManualClock())
```

### `ArchLintTests`/`GenerateFeatureSupportTests`

Los propios plugins (<doc:Generator>, <doc:Lint>) tienen su suite: `ArchLintTests` corre
`archlint` contra fixtures `Good`/`Bad` por regla (R1-R11); `GenerateFeatureSupportTests`
prueba el motor de plantillas (`{{Feature}}`, bloques `{{#flag}}…{{/flag}}`) contra el
mismo fichero que usa el plugin — un symlink, no una copia, así que nunca se desincronizan.
