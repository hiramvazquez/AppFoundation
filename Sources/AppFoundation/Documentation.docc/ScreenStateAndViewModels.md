# Estado de pantalla y view models

`BaseViewModel`, `LoadableViewModel`, `LogicViewModel`, `ScreenState` y `ActionHandling`:
el contrato que separa lo que una pantalla muestra de cómo lo consigue.

## Overview

Cada pantalla separa dos preocupaciones: `phase` (el estado principal — `.idle`,
`.loading`, `.content`, `.empty`, `.error`) y `activity` (trabajo secundario que no
reemplaza el contenido — refresco, envío de formulario, paginación). Usa `phase` para la
carga inicial o un fallo a pantalla completa; usa `activity` para todo lo demás.

### `BaseViewModel`

`@Observable`, `open class`. Las propiedades de una subclase se observan automáticamente
— sin `@Published`, sin `ObservableObject`.

<!-- snippet: quickstart-viewmodel -->
```swift
import AppFoundation
import Observation

struct Profile {
    let name: String
}

@Observable
final class ProfileViewModel: BaseViewModel, ActionHandling {
    private(set) var profile: Profile?

    enum Action: Sendable {
        case load
    }

    func handle(_ action: Action) {
        switch action {
        case .load: load()
        }
    }

    private func load() {
        performLoad { vm in
            vm.profile = Profile(name: "Hiram")
        }
    }
}

let viewModel = ProfileViewModel()
viewModel.handle(.load)
```

`work` recibe el view model como parámetro (`{ vm in ... }`) en vez de capturarlo. No es
una preferencia de estilo: un closure que captura `self` en vez de usar `vm` puede recrear
el ciclo `self → phase → retry → work → self` que esta API existe para evitar.

### `performLoad`/`performActivity` — sin estructurar, devuelven `Task`

Para acciones que deben sobrevivir a un solo tap (un submit por botón):

```swift
performLoad(successTransition: .preserveCurrentPhase) { vm in
    let items = try await vm.service.fetch()
    vm.items = items
    if items.isEmpty { vm.setEmpty() } else { vm.setContent() }
}

performActivity(style: .inline) { vm in
    try await vm.service.sync()
}
```

### `load`/`activity` — estructurado, corre en el `Task` del llamador

Para usar desde `.task`, donde SwiftUI ya cancela al desaparecer la vista:

```swift
.task {
    await viewModel.load { vm in
        vm.items = try await vm.service.fetch()
    }
}
```

### `LogicViewModel<L>`

`open class LogicViewModel<L>: BaseViewModel` con `public let logic: L`. No conforma
`ActionHandling` — cada subclase declara su propio `enum Action`. Es la forma recomendada
de construir un ViewModel sobre una `Logic` (ver <doc:Architecture>):

<!-- snippet: getting-started-viewmodel -->
```swift
import AppFoundation
import Observation

protocol GreetingLogicProtocol: Logic {
    func greeting(for name: String) -> String
}

final class GreetingLogic: GreetingLogicProtocol {
    func greeting(for name: String) -> String {
        "Hola, \(name)"
    }
}

@Observable
final class GreetingViewModel: LogicViewModel<any GreetingLogicProtocol>, ActionHandling {
    private(set) var message: String = ""

    enum Action: Sendable {
        case load(name: String)
    }

    func handle(_ action: Action) {
        switch action {
        case .load(let name): load(name: name)
        }
    }

    private func load(name: String) {
        performLoad { vm in
            vm.message = vm.logic.greeting(for: name)
        }
    }
}

let viewModel = GreetingViewModel(logic: GreetingLogic())
viewModel.handle(.load(name: "Hiram"))
```

### `ActionHandling` y `ActionSender`: un solo punto de entrada

`ActionHandling` (`associatedtype Action: Sendable`, `func handle(_ action: Action)`) es el
ÚNICO método que una vista (o un test) llama — todo lo demás puede ser `private`.
`ScreenContainer`'s `content` closure recibe un `ActionSender<Action>` construido con una
referencia **débil** al view model (`send(.load)`/`sender(.load)`): retener el `send` no
mantiene vivo al view model.

Un `ScreenState` de solo lectura (sin acciones) no necesita `ActionHandling` en absoluto —
`ScreenContainer(observing:)` y `.screen(_:chrome:)` toman un `ScreenState` plano.

### Tests deterministas: `inFlightLoad`/`inFlightActivity`

`handle(_:)` devuelve `Void` — no hay `Task` que esperar en el call site. `BaseViewModel`
expone el que está en vuelo (`nil` al terminar), así que un test nunca sondea `phase` en un
bucle con `Task.sleep`:

<!-- snippet: screenstate-inflight -->
```swift
import AppFoundation
import Observation

@Observable
final class CounterViewModel: BaseViewModel, ActionHandling {
    private(set) var count = 0

    enum Action: Sendable {
        case increment
    }

    func handle(_ action: Action) {
        switch action {
        case .increment: increment()
        }
    }

    private func increment() {
        performLoad { vm in
            vm.count += 1
        }
    }
}

@MainActor
func incrementAndWait() async {
    let viewModel = CounterViewModel()
    viewModel.handle(.increment)
    await viewModel.inFlightLoad?.value
    assert(viewModel.phase == .content)
    assert(viewModel.count == 1)
}

await incrementAndWait()
```

`clock` y `cancellationRecognizer` siguen la misma precedencia que `errorPresenter`
(<doc:ErrorHandling>): instancia > `BaseViewModel.clock`/`.cancellationRecognizer`
(estáticos, para configuración a nivel de app) > default.

## Topics

### Fases y estado

- ``ViewPhase``
- ``ActivityState``
- ``ActivityStyle``
- ``ScreenError``
- ``AlertState``
- ``BannerState``

### View models

- ``BaseViewModel``
- ``LoadableViewModel``
- ``LogicViewModel``

### Contrato pantalla ↔ cáscara

- ``ScreenState``
- ``ActionHandling``
- ``ActionSender``
- ``ScreenViewModel``
