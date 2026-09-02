# Lint

`ArchitectureLint`: build-tool plugin que hace fallar el build si un feature se sale de
View → ViewModel → Logic → Services/Stores. Es lo único que un agente no puede ignorar.

## Overview

```swift
// Package.swift del consumidor
.target(
    name: "MiApp",
    dependencies: [...],
    plugins: [.plugin(name: "ArchitectureLint", package: "AppFoundation")]
)
```

Cada `swift build`/build de Xcode corre `archlint` sobre `target.sourceFiles` antes de
compilar; una violación hace fallar el build con un diagnóstico navegable en Xcode:

```
Sources/MiApp/Features/Login/LoginViewModel.swift:2:1: error: [ArchLint.R1] El ViewModel no debe importar CoreNetworking — delega en su Logic (any XxxLogicProtocol).
```

**Desde Xcode**: selecciona el target → Build Phases → **Run Build Tool Plug-ins** → **+**
→ `ArchitectureLint`.

**Para CI**, el mismo ejecutable como command plugin, sin integrarlo en ningún target:

```bash
swift package archlint [--path DIR]
```

### Las reglas (R1-R11)

Análisis léxico propio (tokens, `import`, declaraciones de tipo; ignora comentarios y
strings), clasificando cada fichero por el sufijo de su nombre (`XxxViewModel.swift`,
`XxxView.swift`, `XxxLogic.swift`, `Services/XxxService.swift`, `Stores/XxxStore.swift`,
`XxxModule.swift` — el composition root, exento de casi todas las reglas). Código dentro de
`#if DEBUG`/`#Preview { … }` está exento: es andamiaje de previsualización, no producción.

| Regla | Qué comprueba |
|---|---|
| **R1** | El ViewModel no importa CoreNetworking ni referencia `APIService`/`URLSession`/`*Service`/`*Store`; conforma `ActionHandling`. Con `strict: true`, exige heredar de `LogicViewModel`. |
| **R2** | La Logic no importa SwiftUI/UIKit ni referencia `*ViewModel`; declara su propio `protocol XxxLogicProtocol: Logic`. |
| **R3** | Un Service declara `protocol XxxServicing: Sendable`; un Store declara `protocol XxxStoring: Sendable`. Ninguna otra capa toca `APIServiceProtocol`/`BaseRequest`/SwiftData/CoreData directamente. |
| **R4** | La View no referencia `*Logic`/`*Service`/`*Store`/`APIService`. |
| **R5** | Cada `XxxViewModel.swift` (que hereda `LogicViewModel`) tiene su `XxxLogic.swift`. Desactivable por pantalla vía `ignore:`. |
| **R6** | Ningún `init` de otra capa recibe un `Service`/`Store`/`Logic` CONCRETO: siempre `any XxxProtocol`. |
| **R7** | `APIError` no llega al ViewModel/View; `import CoreNetworking` solo permitido en Logic y Services. |
| **R8** | Los DTOs (`*Request`/`*Response`/`*DTO`) no salen del Service/Store. |
| **R9** | Logic/Service/Store no referencian `Router`/`Coordinator`/`DeepLink`. |
| **R10** | `Container.shared`/`resolve(`/`@Inject` prohibidos fuera del `XxxModule` (composition root). |
| **R11** | Aviso (no error): una Logic marcada `@MainActor` pierde su independencia de actor. |

### `.archlint.yml`

Formato propio, mínimo: `key: value` plano, listas en bloque (`- item`) o inline (`[a,
b]`) — sin librería YAML. `archinit` escribe uno con los valores por defecto documentados;
sin fichero, `archlint` usa esos mismos defaults (incluido ignorar `Tests/**` y los
dobles de test).

```yaml
strict: false                      # exige LogicViewModel en cada ViewModel (extiende R1)
suffixes.viewModel: ViewModel
suffixes.logic: Logic
suffixes.service: Service
suffixes.store: Store
disabled: [R11]                    # reglas desactivadas por id
ignore:                            # rutas ignoradas (glob: '*' un segmento, '**' cualquiera)
  - Generated/**
```

## Ver también

- <doc:Generator> — el camino fácil: el cascarón que ya cumple estas reglas.
- <doc:Architecture> — de dónde sale cada regla (§1 y las mejoras M1-M11).
