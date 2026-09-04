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

Otras opciones: `--module` (M8: separa Core/UI en subcarpetas — o en dos targets reales,
ver «Modo multi» abajo), `--analytics` (M10: deja el hueco para inyectar un tracker en la
Logic), `--no-logic` (solo para una pantalla sin regla de negocio propia — úsalo poco),
`--no-tests`, `--path Features` (carpeta destino, ignorada en modo multi), `--dry-run`
(lista lo que generaría sin escribir nada).

### Modo multi (PRD-AF-10)

Si este proyecto tiene un `.archinit-multi` en la raíz del paquete donde se invoca el
comando (lo deja `archinit --multi`), cada feature es un target real —
`Sources/<Nombre>Feature/…`, o `<Nombre>FeatureCore`/`<Nombre>FeatureUI` con `--module` —
y el generador da de alta el target y el producto en `Package.swift`, e inserta
`<Nombre>Module()`/`case <nombre>` en `App/AppModule.swift`/`App/AppRoute.swift` si esos
ficheros y sus markers existen. `--no-register` desactiva las tres ediciones (el feature
se genera igual, sin registrar nada). Si el target ya existe o falta un marker, el
comando falla con un error claro sin tocar ni el manifiesto ni los ficheros del feature.
Fuera de ese `.archinit-multi`, nada de esto aplica — comportamiento idéntico al de
siempre.

¿La pantalla necesita el Service/Store de OTRO feature ya generado (p. ej. el detalle de un
producto reutilizando `ProductsServicing`)? `--service-from <Feature>`/`--store-from
<Feature>` en vez de generar uno nuevo: la Logic depende de `any <Feature>Servicing`/`any
<Feature>Storing`, y no se genera `XxxService`/`XxxStore` — recuerda registrar también el
`Module` del feature reutilizado.

```bash
swift package --allow-writing-to-package-directory generate-feature Products --api
swift package --allow-writing-to-package-directory generate-feature Detail --api --service-from Products
```

Si todavía no hay ningún feature del que reutilizar, pero tampoco quieres un
`XxxService`/`XxxStore` generado ahora mismo: `--no-service`/`--no-store` — la Logic recibe
igualmente `any XxxServicing`/`any XxxStoring` (como placeholder con un `// TODO`), sin
generar el tipo concreto ni sus mocks/tests. No combina con `--api --local` a la vez (usa
`--service-from`/`--store-from` para ese caso).

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

Antes de dar la feature por terminada: `swift build` (corre ArchitectureLint y SwiftLint),
`swift test`, y pega la última línea de cada uno. `swiftlint lint --strict Sources Tests` si
está instalado.
