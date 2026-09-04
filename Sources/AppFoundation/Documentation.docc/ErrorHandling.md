# Errores

`ErrorPresenting`, `DomainError`, `AppErrorConvertible`, `CancellationRecognizing` y
`WrappedError`: cómo un error se convierte en copy de pantalla, una sola vez, en un solo
sitio.

## Overview

`performLoad`/`performActivity` nunca muestran `error.localizedDescription` de un `Error`
ajeno — para un enum de dominio típico esa cadena lee *"The operation couldn't be
completed. (Module.Type error 9.)"*, algo que nunca debería llegar a pantalla. En su lugar,
todo error pasa por un `ErrorPresenting`.

### `ErrorPresenting`: el único sitio que mapea errores a copy

```swift
public protocol ErrorPresenting: Sendable {
    func screenError(for error: any Error, fallbackTitle: String, retry: Action?) -> ScreenError
}
```

`BaseViewModel.errorPresenter` (`static var`, por defecto `DefaultErrorPresenter()`) se
configura una vez al arrancar la app y beneficia a toda pantalla sin tocar cada view model.
Un view model puede pisarlo para sí mismo vía `BaseViewModel(errorPresenter:)`. Precedencia:
instancia > `BaseViewModel.errorPresenter` > `DefaultErrorPresenter()`.

`DefaultErrorPresenter` resuelve en este orden:

1. `AppErrorConvertible` — el error ya sabe presentarse.
2. `LocalizedError` con `errorDescription` no nulo — el título de fallback más esa
   descripción.
3. Cualquier otra cosa — título de fallback más un mensaje genérico localizado; el detalle
   técnico se loguea (`AppFoundationLogger.errors`, `.private`), nunca se muestra.

### `DomainError`: la frontera entre una capa que sabe de red/persistencia y el resto

Un `Service` lanza lo que su transporte produce (`APIError`, un error de SwiftData); la
`Logic` lo traduce a un error del propio feature ANTES de devolverlo — el `ViewModel` y el
`ErrorPresenting` nunca ven el error de transporte, solo `DomainError`. Es lo que hace que
`ErrorPresenting` funcione igual en las cuatro variantes de <doc:Architecture>.

```swift
public protocol DomainError: Error, AppErrorConvertible, Sendable {
    var isRetryable: Bool { get }   // default: false
}
```

<!-- snippet: errors-domain-and-presenter -->
```swift
import AppFoundation

enum LoginError: DomainError {
    case invalidCredentials
    case offline

    var isRetryable: Bool {
        switch self {
        case .offline: true
        case .invalidCredentials: false
        }
    }

    var screenError: ScreenError {
        switch self {
        case .invalidCredentials:
            return ScreenError(title: "Credenciales inválidas", message: "Revisa tu email y contraseña.")
        case .offline:
            return ScreenError(title: "Sin conexión", message: "Revisa tu red e inténtalo de nuevo.")
        }
    }
}

struct AppErrorPresenter: ErrorPresenting {
    func screenError(for error: any Error, fallbackTitle: String, retry: Action?) -> ScreenError {
        if let domain = error as? any DomainError {
            return domain.screenError
        }
        return DefaultErrorPresenter().screenError(for: error, fallbackTitle: fallbackTitle, retry: retry)
    }
}

// Al arrancar la app:
BaseViewModel.errorPresenter = AppErrorPresenter()
```

### `AppErrorConvertible`: un error que se presenta a sí mismo

La vía más simple para conectar un error de dominio: no requiere ningún `ErrorPresenting`
propio, solo `var screenError: ScreenError { get }`. `WrappedError` conforma así.

### Cancelación

Una carga cancelada nunca llega a `.error`. Más allá de `CancellationError` tipado,
`BaseViewModel.cancellationRecognizer` (por defecto también reconoce
`URLError(.cancelled)`) se consulta también — amplíalo si el tipo de error de tu app envuelve
la cancelación de otra forma:

```swift
struct AppCancellationRecognizer: CancellationRecognizing {
    func isCancellation(_ error: any Error) -> Bool {
        DefaultCancellationRecognizer().isCancellation(error)
            || (error as? MyNetworkError)?.isCancellation == true
    }
}
BaseViewModel.cancellationRecognizer = AppCancellationRecognizer()
```

Si tu `Logic` ya traduce el error de red a tu propio `DomainError` antes de devolverlo (M1,
lo normal en las cuatro variantes de <doc:Architecture>), el `ViewModel` nunca ve el error de
red original — solo el `DomainError` ya mapeado. Tu recognizer tiene que reconocer AMBAS
formas: la de red (por si algún camino la deja pasar sin traducir) y la ya mapeada (para el
camino normal). `Examples/LoginApp` (`AppCancellationRecognizer.swift`,
`LoginLogic.mapError`) es el ejemplo completo de esta costura con CoreNetworking:
`APIError(code: .cancelled)` se traduce a `LoginError.cancelled` — nunca a `.unknown` — y el
recognizer reconoce los dos, `APIError.isCancellation` y `LoginError.cancelled`.

## Topics

### Presentación

- ``ErrorPresenting``
- ``DefaultErrorPresenter``

### Dominio

- ``DomainError``
- ``AppErrorConvertible``
- ``WrappedError``

### Cancelación

- ``CancellationRecognizing``
- ``DefaultCancellationRecognizer``
