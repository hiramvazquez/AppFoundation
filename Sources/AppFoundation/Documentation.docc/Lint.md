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

### Las reglas (R1-R16)

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
| **R12** | Aviso (no error): en una `*View.swift`, `let viewModel:`/`var viewModel:` sin `@State` en la misma línea o la anterior — un ViewModel transitorio se libera cuando SwiftUI reevalúa el builder de destino y pierde la acción `.load` (PRD-X-05, A3/A7). |
| **R13** | Aislamiento entre módulos (PRD-AF-10, repo multi-target): cada `import` de un fichero se compara contra `forbiddenImports`/`allowedImports` del módulo al que pertenece — ver `modules:` más abajo. Sin `modules:` en la config, no hace nada. |
| **R15** | Error: una `class` cuyo nombre termina en `ViewModel` sin `@Observable`. El macro no se hereda de `BaseViewModel`: sin él, las propiedades propias del ViewModel no refrescan la vista, y la pantalla solo se actualiza cuando cambia `phase`/`activity` por coincidencia (PRD-AF-11, A0). |
| **R16** | Error: una `class` (no `nonisolated`, no `actor`) sin su propio `deinit`. Bajo `defaultIsolation(MainActor)` el compilador sintetiza un `deinit` aislado que en sistemas anteriores al runtime del toolchain pasa por un shim que abortó en iOS 26.2 (`docs/repros/isolated-deinit-backdeploy.md`); `deinit {}` explícito es nonisolated y lo evita (PRD-AF-11, A8). La comprobación es por clase: un `deinit` en otra clase del mismo fichero (o en una clase que la contiene, si está anidada) no la exime. |
| **R14** | Aviso (no error): una dependencia de `Package.swift` fijada por `branch:`/`revision:` en vez de un tag — no reproducible. Solo lo comprueba `swift package archlint` (command plugin); el build-tool plugin nunca ve `Package.swift`. |

### R13 — aislamiento entre módulos

Pensada para el repo de tres niveles de `archinit --multi` (PRD-AF-10: `Domain`/`<Cap>Kit`/
`<Sdk>Adapters` en `Packages/Platform`, `<Name>Feature` en `Packages/Features`), pero
funciona en cualquier repo con varios targets. El **módulo** de un fichero es el segmento
que sigue a `Sources/` en su ruta relativa (`Sources/MisCasosFeature/…` → `MisCasosFeature`;
con `generate-feature --module` en modo multi, `Sources/MisCasosFeatureCore/…` →
`MisCasosFeatureCore`, sin tratamiento especial: es literalmente el nombre del target). El
build-tool plugin (`ArchitectureLint`) no necesita adivinarlo por la ruta: pasa
`--module <sourceModule.name>` con el nombre real del target de SwiftPM, que manda sobre
la ruta cuando está presente. El command plugin (`swift package archlint`, que puede
recorrer varios targets en una sola pasada) sí lo calcula por ruta, fichero a fichero.

Por cada `import X` del fichero (excepto `import Testing`/`XCTest`, que nunca cuentan — y
los tests ya están fuera por el `ignore:` por defecto): si `X` casa con `forbiddenImports`
del módulo → error; si el módulo declara `allowedImports` y `X` no casa con ninguna entrada
→ error. La búsqueda del módulo en `modules:` es primero una coincidencia EXACTA del nombre
(gane la posición que gane en el fichero), y si no hay ninguna, la primera entrada cuyo glob
casa, en el orden en que aparecen. Sin entrada aplicable (ni exacta ni por glob), R13 no
dice nada de ese fichero.

El mensaje cambia según qué se importa: si el módulo importado también termina en
`Feature`, "las features se comunican por Domain y por AppRoute"; si no (un SDK, un `*Kit`,
un `*Adapters`), "entra por un protocolo de Domain implementado en un Adapter/Kit".

```
Sources/MisCasosFeature/MisCasosView.swift:3:1: error: [ArchLint.R13] 'MisCasosFeature' no puede importar 'IndemnizacionesFeature': las features se comunican por Domain y por AppRoute.
```

#### `modules:`

Dos formas equivalentes — usa la que prefieras, no hace falta elegir una para todo el
fichero:

**Anidada** (la de referencia; dos niveles, con la indentación real de YAML — la única
sección de `.archlint.yml` donde `archlint` la respeta, ver nota abajo):

```yaml
modules:
  Domain:
    allowedImports: [Foundation]
  CameraKit:
    allowedImports: [Foundation, Domain, AVFoundation, UIKit, SwiftUI]
  FirebaseAdapters:
    allowedImports: [Foundation, Domain, Firebase*]
  "*Feature":                          # las comillas son obligatorias: '*' no es válido
    allowedImports: [Foundation, SwiftUI, Observation, AppFoundation, CoreNetworking, Domain]
    forbiddenImports: ["*Feature", "Firebase*", "*Kit", "*Adapters"]
```

**Plana** (clave con puntos, como el resto de `.archlint.yml` — sin indentación, así que no
necesita comillas alrededor del `*`):

```yaml
modules.Domain.allowedImports: [Foundation]
modules.*Feature.allowedImports: [Foundation, SwiftUI, Domain]
modules.*Feature.forbiddenImports: [*Feature, Firebase*]
```

Los nombres de módulo y las entradas de `allowedImports`/`forbiddenImports` son globs
(`*Feature`, `Firebase*`; mismo motor que `ignore:`, `Glob.swift`).

#### Dónde vive `.archlint.yml` con `modules:`

Hoy `archlint` busca `.archlint.yml` en `--root`/`--config` (el directorio del PAQUETE). En
un repo multi-paquete, cada paquete (`Packages/Platform`, `Packages/Features`) tiene el suyo
para sus reglas de capa (R1-R12), y `modules:` vive en el `.archlint.yml` de la RAÍZ del
repo, un nivel — o más — por encima. La resolución, en este orden:

1. Si el `.archlint.yml` del paquete YA trae `modules:`, se usa tal cual (caso de un repo
   de un solo paquete que también es la raíz) — no se sube ningún directorio.
2. Si no, `archlint` sube desde `--root` por cada directorio padre buscando un
   `.archlint.yml` con una sección `modules:` no vacía, y se queda con la primera que
   encuentra (fusiona SOLO esa sección; el resto de ese fichero raíz —`strict:`,
   `suffixes.*`…— no se aplica al paquete).
3. `--modules-config PATH` fuerza un fichero concreto, saltándose los dos pasos
   anteriores — para CI o una comprobación puntual.

Sin `modules:` en ninguno de los dos sitios, R13 no emite ningún diagnóstico:
compatibilidad total con un proyecto que nunca adoptó el modo multi-módulo.

### R14 — dependencia por rama o commit

Solo en `swift package archlint` (el command plugin añade `--check-package-swift`; el
build-tool plugin nunca ve `Package.swift`, no es uno de los `sourceFiles` de ningún
target). Busca `branch:`/`revision:` usados como argumento de `.package(url:branch:)`/
`.package(url:revision:)` en el `Package.swift` de `--root` — léxico, como el resto de
`archlint`: no distingue un argumento real de, por ejemplo, un comentario citándolo
literalmente solo si el comentario ya fue eliminado por el lexer (lo es). Aviso, nunca
rompe el build:

```
Package.swift:5:9: warning: [ArchLint.R14] Dependencia por rama/commit ('branch:' en Package.swift): no es reproducible; usa un tag.
```

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

#### Qué se ignora, y qué se ignora siempre

Hay dos listas, y conviene saber cuál es cuál:

- **`ignore:`** — la lista del usuario. Sin fichero (o sin la clave), vale por defecto
  `**/Tests/**`, `**/*Tests.swift`, `**/*Mock.swift`, `**/*Mocks.swift`, `**/*Spy.swift` y
  `**/*Stub.swift`. Un `ignore:` explícito **reemplaza** esos defaults, no los amplía — es
  la única forma de dejar de ignorar `Tests/**` si algún día lo necesitas. El `.archlint.yml`
  que escribe `archinit` es explícito (`Tests/**` y `**/Mocks/**`), así que en un proyecto
  inicializado con `archinit` los defaults ya no aplican.
- **Siempre ignoradas** — `**/.build/**`, `**/.swiftpm/**`, `**/DerivedData/**` y
  `**/.git/**`, aplicadas en toda ejecución, diga lo que diga `ignore:`. Ahí viven las
  dependencias descargadas (`.build/checkouts` contiene las fuentes de cada dependencia,
  incluidos los fixtures «malos» con los que AppFoundation prueba su propio linter) y los
  productos de build; nunca tu código. Antes de 1.0.1 estas rutas vivían dentro de los
  defaults de `ignore:`, y un `ignore:` explícito las borraba con el resto: `swift package
  archlint` sin `--path` entraba en `.build/checkouts` y fallaba por código ajeno.

El build-tool plugin (`ArchitectureLint`) no se ve afectado por nada de esto: recibe solo
los `sourceFiles` del target. La distinción importa para el command plugin (`swift package
archlint`), que sin `--path` recorre el directorio del paquete entero.

## Ver también

- <doc:Generator> — el camino fácil: el cascarón que ya cumple estas reglas.
- <doc:CodeQuality> — la otra capa: SwiftLint curado para CÓMO está escrito el código.
- <doc:Architecture> — de dónde sale cada regla (§1 y las mejoras M1-M11).
