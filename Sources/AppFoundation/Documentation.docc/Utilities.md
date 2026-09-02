# Utilidades

`Debouncer`, `Throttler` y `AppEnvironment`: piezas pequeñas, sin estado global oculto.

## Overview

### `Debouncer` / `Throttler`

`@MainActor final class`, no `actor`: su estado solo lo toca el llamador, así que
`debounce`/`throttle` corren síncronamente en el main actor — sin `Task`, sin `await` en el
call site. El reloj es `any Clock<Duration>` (por defecto `ContinuousClock`); los tests
inyectan un reloj manual para aserciones deterministas y sin esperas reales. `deinit`
cancela cualquier trabajo en vuelo.

@Snippet(path: "AppFoundation/Snippets/utilities-debouncer")

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
