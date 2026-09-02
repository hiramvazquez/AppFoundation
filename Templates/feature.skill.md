---
name: feature
description: Genera un feature completo (View → ViewModel → Logic → Services/Stores) con el generador de AppFoundation, y recuerda las reglas de arquitectura que ArchitectureLint hace cumplir. Úsalo cuando el usuario pida crear una pantalla/feature nueva en un proyecto que depende de AppFoundation.
---

# /feature — generador de features de AppFoundation

Instalado por `swift package --allow-writing-to-package-directory archinit`
(`AppFoundation`). Este proyecto sigue la arquitectura
**View → ViewModel → Logic → Services/Stores** (`AGENTS.md` en la raíz del proyecto —
léelo antes de tocar código de un feature).

## Generar un feature

```bash
swift package --allow-writing-to-package-directory generate-feature <Nombre> [opciones]
```

Elige las opciones según de qué depende la pantalla:

| Variante | Opciones | Logic depende de |
|---|---|---|
| Solo API | `--api` | `any XxxServicing` |
| Solo local | `--local` | `any XxxStoring` (SwiftData) |
| API + local | `--api --local` | ambos, política cache-then-network |
| Sin datos | (ninguna) | nada — Logic sigue existiendo, pura |

Otras opciones: `--module` (M8: separa Core/UI en subcarpetas), `--analytics` (M10: deja el
hueco para inyectar un tracker en la Logic), `--no-logic` (solo para una pantalla sin
regla de negocio propia — úsalo poco), `--no-tests`, `--path Features` (carpeta destino),
`--dry-run` (lista lo que generaría sin escribir nada).

Ejemplo real:

```bash
swift package --allow-writing-to-package-directory generate-feature Login --api
```

Genera `Features/Login/{LoginView,LoginViewModel,LoginLogic,LoginModule}.swift`,
`Features/Login/Services/LoginService.swift`, y sus tests + mocks en el target de tests.
**Todo compila y sus tests pasan desde el primer segundo.**

## Después de generar

El generador imprime los pasos que NO automatiza (nunca edita el `.xcodeproj` ni el
`enum AppRoute`):

1. Añade el `case` correspondiente a tu `enum AppRoute` y su ruta en el `CoordinatorView`.
2. Registra `XxxModule` en el arranque de la app: `Container.shared.register(modules: [...])`.
3. Si el proyecto no usa carpetas sincronizadas (Xcode 16+), arrastra la carpeta generada
   al target.

## Las reglas que el linter hace cumplir (ArchitectureLint / `archlint`)

Corre en cada build (si el plugin está en el target) y en CI (`swift package archlint`).
Un error de build es lo único que un agente no puede ignorar — por eso importa conocer las
reglas ANTES de escribir el código a mano:

- **R1** — el ViewModel no importa CoreNetworking ni referencia `APIService`/`URLSession`/
  `*Service`/`*Store`; solo `any XxxLogicProtocol` por `init`. Conforma `ActionHandling`.
- **R2** — la Logic no importa SwiftUI/UIKit ni referencia `*ViewModel`; declara su propio
  `protocol XxxLogicProtocol: Logic`.
- **R3** — solo un Service toca `APIServiceProtocol`/`BaseRequest`; solo un Store toca
  SwiftData/CoreData/UserDefaults/Keychain/FileManager.
- **R4** — la View no referencia `*Logic`/`*Service`/`*Store`/`APIService` (salvo en
  `#Preview`/`#if DEBUG`, que el linter no analiza).
- **R5** — cada `XxxViewModel.swift` tiene su `XxxLogic.swift`.
- **R6** — ningún `init` de otra capa recibe un `Service`/`Store`/`Logic` CONCRETO: siempre
  `any XxxProtocol`.
- **R7** (M1) — `APIError` nunca llega al ViewModel/View; la Logic lo traduce a un
  `DomainError` propio del feature.
- **R8** (M2) — los DTOs (`*Request`/`*Response`/`*DTO`) no salen del Service/Store.
- **R9** (M3) — Logic/Service/Store no referencian `Router`/`Coordinator`/`DeepLink`: la
  navegación la decide el ViewModel.
- **R10** (M4) — nada de `Container.shared`/`resolve(`/`@Inject` fuera del `XxxModule`
  (composition root).
- **R11** (M5, aviso) — una Logic marcada `@MainActor` pierde su independencia de actor;
  normalmente es `nonisolated`.

## Qué NO hacer

- No escribas un Service/Store a mano cuando el generador ya te da uno correcto — genera
  con `--api`/`--local` y ajusta el cuerpo.
- No inyectes un tipo concreto en un `init` — siempre `any XxxProtocol` (R6).
- No dejes que un error de red/persistencia llegue al ViewModel — mapéalo a `DomainError`
  dentro de la Logic (R7, M1).
- No llames a `Container.shared` desde dentro de una Logic/Service/Store — regístralo y
  resuélvelo desde el `XxxModule` (R10, M4).

Ver también `AGENTS.md` (raíz del proyecto) y, en el paquete AppFoundation,
`AppFoundation/README.md` § Generador y linter.
