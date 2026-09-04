# Utilidades

`Debouncer`, `Throttler` y `AppEnvironment`: piezas pequeñas, sin estado global oculto.

## Overview

### `Debouncer` / `Throttler`

`@MainActor final class`, no `actor`: su estado solo lo toca el llamador, así que
`debounce`/`throttle` corren síncronamente en el main actor — sin `Task`, sin `await` en el
call site. El reloj es `any Clock<Duration>` (por defecto `ContinuousClock`); los tests
inyectan un reloj manual para aserciones deterministas y sin esperas reales. `deinit`
cancela cualquier trabajo en vuelo.

<!-- snippet: utilities-debouncer -->
```swift
import AppFoundation
import Observation

@Observable
final class SearchViewModel: BaseViewModel {
    // Nonisolated on purpose: without an explicit deinit the compiler synthesizes an isolated
    // one that goes through a back-deploy shim on older OS versions (see AppFoundation's
    // `docs/repros/isolated-deinit-backdeploy.md`). Nothing to clean up here.
    deinit {}

    private let debouncer = Debouncer(delay: .milliseconds(300))
    private(set) var query = ""

    func onQueryChanged(_ text: String) {
        query = text
        debouncer.debounce { [weak self] in
            self?.search()
        }
    }

    private func search() {
        performActivity { _ in
            // await apiService.search(query)
        }
    }
}
```

`Throttler` tiene la misma forma: ejecuta como mucho una vez por ventana, en vez de
esperar a que las llamadas paren.

### `AppEnvironment`

`enum` namespace (sin estado que instanciar): `isDebug`, `isTestFlight`, `isSimulator`,
`appVersion`, `deviceModel`, `physicalMemoryFormatted`, etc. No ofrece una bandera
"¿esto corre bajo tests o previews?" — inyecta el comportamiento que quieres en tests en
vez de preguntarle al entorno.

```swift
if AppEnvironment.isSimulator {
    // solo para depuración local
}
```

## Topics

### Timing

- ``Debouncer``
- ``Throttler``

### Entorno

- ``AppEnvironment``
