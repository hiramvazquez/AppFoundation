# Inyección de dependencias

`Container`, `DependencyModule`, `Lifecycle` e `@Inject`: el composition root, `@MainActor`,
sin `NSLock` ni `@unchecked Sendable`.

## Overview

`Container` es `@MainActor`: el compilador garantiza que las fábricas de tipos
`@MainActor` corren en el main actor, y llamar `resolve()` desde un contexto `nonisolated`
es un error de compilación, no una convención documentada.

### Composition root

Registra una vez, al arrancar, con un `DependencyModule` por feature:

```swift
struct ProfileModule: DependencyModule {
    func register(in container: Container) {
        container.register(ProfileRepository.self) { _ in LiveProfileRepository() }
        // La fábrica recibe el container en el que se registró: resuelve sus propias
        // dependencias desde ahí, nunca de un global.
        container.register(ProfileSyncService.self) { c in
            ProfileSyncService(repository: c.resolve())
        }
    }
}

Container.shared.register(modules: [ProfileModule()])
```

`register(_:lifecycle:factory:)` por defecto es `.singleton` (una instancia por
contenedor, perezosa); `.transient` construye una por resolución. Un objeto que ya tienes
entra con `register(instance:as:)`.

### Un contenedor hijo por flujo

`Container.shared` es un `static let`: nunca se sustituye. Un checkout, una sesión, un
wizard — dependencias que sobreviven a una pantalla pero no a la app — van en un
contenedor **hijo**, sin scope con clave de cadena que crear/destruir a mano:

@Snippet(path: "AppFoundation/Snippets/di-child-container")

Una fábrica registrada en el padre se resuelve desde el padre incluso a través de un hijo:
sustituir `ProfileRepository` en un hijo de test nunca reconstruye el singleton de
`Container.shared` con el doble.

### Qué mecanismo, cuándo

| Construyes | Usa | Por qué |
|---|---|---|
| View models, services, repositorios | `init` | La dependencia está en la firma; el compilador la comprueba; los tests pasan un doble. |
| Vistas | `Environment` (`@Entry`) | Con alcance al árbol de vistas, sobreescribible por subárbol, entendido por previews. |
| Clases hoja donde pasar la dependencia por `init` cuesta más que aclara | `@Inject` | Último recurso: esconde la dependencia y hace `trap` en runtime si no está registrada. |

### Ciclos

Una fábrica que resuelve el tipo que está construyendo (A → B → A) hace `trap` con un
mensaje que nombra todos los tipos implicados en el ciclo — rómpelo pasando un lado por su
`init`.

## Topics

### Composition root

- ``Container``
- ``DependencyModule``
- ``Lifecycle``

### Último recurso

- ``Inject``
