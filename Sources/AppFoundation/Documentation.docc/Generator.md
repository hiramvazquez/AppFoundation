# Generador

`generate-feature`: el cascarón View → ViewModel → Logic → Services/Stores de un feature,
generado en segundos, compilando y con sus tests en verde desde el primer momento.

## Overview

Command plugin de SwiftPM — no viaja en el binario de producción. Se invoca desde el
proyecto que consume AppFoundation:

```bash
swift package --allow-writing-to-package-directory generate-feature Login --api
swift package --allow-writing-to-package-directory generate-feature Notes --local
swift package --allow-writing-to-package-directory generate-feature Catalog --api --local
swift package --allow-writing-to-package-directory generate-feature Counter
```

**Desde Xcode**: clic derecho sobre el proyecto en el navegador → el plugin aparece en el
menú contextual (Xcode 14+) → pide permiso de escritura una vez.

### Opciones

| Opción | Qué hace |
|---|---|
| `--api` | La Logic depende de `any XxxServicing`; genera `Services/XxxService.swift`. |
| `--local` | La Logic depende de `any XxxStoring` (SwiftData); genera `Stores/XxxStore.swift`. |
| `--api --local` | Ambos, con la política cache-then-network de `CatalogApp` (M7, <doc:Architecture>). |
| (ninguna) | La Logic no depende de nada — sigue existiendo como tipo, pura. |
| `--module` | M8: separa el feature en `XxxCore/`/`XxxUI/` e imprime el snippet de `Package.swift` para promoverlas a targets reales. |
| `--analytics` | Deja el hueco documentado para inyectar un tracker en la Logic (M10). |
| `--no-logic` | Sin Logic: el ViewModel hereda `BaseViewModel` directamente — solo para una pantalla sin regla de negocio propia. |
| `--no-tests` | Omite los tests/mocks generados. |
| `--path Features` | Carpeta destino dentro del target (por defecto `Features`). |
| `--target NAME` | Target de origen, si el paquete tiene más de uno. |
| `--dry-run` | Lista lo que generaría sin escribir nada. |
| `--route AppRoute.xxx` | Se imprime en los pasos manuales, como recordatorio. |
| `--no-service` / `--no-store` | La Logic sigue dependiendo de `any XxxServicing`/`any XxxStoring`, pero no se genera `XxxService`/`XxxStore` (ni sus mocks/tests): el protocolo queda como placeholder con un `// TODO` en `XxxLogic.swift`, y `XxxModule` deja el `// TODO` de registro. |
| `--service-from <Feature>` / `--store-from <Feature>` | La Logic depende de `any <Feature>Servicing`/`any <Feature>Storing` — el `Servicing`/`Storing` de OTRO feature ya generado. No se genera `XxxService`/`XxxStore` nuevo; `XxxModule` no registra nada (lo hace el módulo del feature reutilizado); los tests de la Logic usan el mock real de ese feature (`<Feature>ServiceMock`/`InMemory<Feature>Store`). Implican `--api`/`--local` respectivamente. |

`--no-service`/`--no-store` no combinan con `--api --local` a la vez (el error lo explica:
los tests de Logic para esa combinación ejercitan Service y Store juntos, y no hay mock
para el lado omitido) — para reutilizar ambas dependencias de otros features con
`--api --local`, usa `--service-from`/`--store-from` en su lugar, que sí combinan
libremente entre sí y con el resto de opciones.

### Reutilizar el Service/Store de otro feature

```bash
swift package --allow-writing-to-package-directory generate-feature Products --api
swift package --allow-writing-to-package-directory generate-feature Detail --api --service-from Products
```

`DetailLogic` recibe `any ProductsServicing` por `init` (no un `DetailServicing` nuevo);
`DetailModule` no registra ningún `Servicing` — lo hace `ProductsModule`, que también debe
estar registrado en el `Container`. `DetailLogicTests` construye un `ProductsServiceMock()`
en vez de un `DetailServiceMock` inexistente.

### Qué genera

Cada variante genera el cascarón completo del kit de arquitectura: un error de dominio
`XxxError: DomainError` con el mapeo desde `APIError` en la Logic (M1), DTOs que no salen
del Service/Store (M2), el `XxxModule: DependencyModule` como composition root (M4), un
`#Preview` con un stub de Logic, y mocks/spies con contadores por protocolo (M9) en el
target de tests. Todo compila y sus tests pasan desde el primer segundo — la referencia
completa vive en `Examples/`.

Límites honestos, iguales para un humano y para un agente: el generador escribe ficheros,
**nunca** edita el `.xcodeproj` (los proyectos con carpetas sincronizadas de Xcode 16+ lo
recogen solos; los antiguos requieren arrastrar la carpeta) ni añade el `case` al `enum
AppRoute` — los imprime como pasos siguientes al terminar. En **modo multi** (ver abajo)
el generador sí añade ese `case` (y el alta en `AppModule`), porque ahí sabe dónde: los
markers documentados por `archinit --multi`.

## Modo multi

PRD-AF-10: cuando el paquete donde se invoca `generate-feature` (el paquete `Features` de
una app modular de tres niveles: cáscara `App/` + `Packages/Platform` + `Packages/
Features`) contiene un fichero `.archinit-multi` en su raíz — lo deja `archinit --multi`
(`Plugins/ArchInit`) —, el generador cambia de comportamiento:

- Cada feature es un **target real** propio: `Sources/<Nombre>Feature/…` y
  `Tests/<Nombre>FeatureTests/…`, en vez de una subcarpeta `Features/<Nombre>/` dentro de
  un target existente. `--module` genera DOS targets reales — `<Nombre>FeatureCore`
  (Logic/Service/Store/Module, sin SwiftUI) y `<Nombre>FeatureUI` (View/ViewModel,
  depende de Core) — en vez de las subcarpetas `<Nombre>Core`/`<Nombre>UI` que produce
  fuera de modo multi.
- El generador **da de alta el target (o los dos) y su test target** entre
  `// archinit:features-begin` / `// archinit:features-end` en la sección `targets:` del
  `Package.swift` del paquete `Features`, y el producto `.library(name: "<Nombre>Feature",
  targets: […])` entre `// archinit:products-begin` / `// archinit:products-end` en
  `products:` — la única edición de manifiesto que hace este generador, y solo en modo
  multi. Dependencias: `AppFoundation` y `Domain` (producto del paquete local `Platform`)
  siempre; `CoreNetworking` solo con `--api`. `ArchitectureLint` se añade al target Core
  siempre y al target único (sin `--module`) siempre; al target UI de un `--module` NO se
  le añade — ver la nota en el código (`MultiMode.swift`): la regla R5 ("un ViewModel
  tiene su Logic") la comprueba el build-tool plugin mirando solo los ficheros del target
  que está compilando, y en modo `--module` la Logic vive en el otro target — `swift
  package archlint` (que sí recorre el paquete entero) sigue comprobando UI igualmente.
  Si ya existe un `.plugin(name: "SwiftLintBuildToolPlugin", …)` en el manifiesto, se
  reutiliza tal cual en los targets nuevos.
- Si el target ya está registrado, o si los markers no existen, el comando **falla con un
  error claro y no toca nada** — ni el `Package.swift` ni los ficheros del feature: la
  validación del manifiesto ocurre ANTES de escribir un solo fichero generado.
- Además, si `../../App/AppModule.swift` existe y tiene el marker `// archinit:modules`,
  se inserta `<Nombre>Module(),`; si `../../App/AppRoute.swift` existe y tiene
  `// archinit:routes`, se inserta `case <nombre>`. Estas dos ediciones son best-effort:
  si el fichero o el marker no existen, el generador no falla — imprime el paso manual,
  igual que fuera de modo multi.
- `--no-register` desactiva las tres ediciones (Package.swift, AppModule.swift,
  AppRoute.swift): el generador solo escribe los ficheros del feature.

```bash
cd Packages/Features
swift package --allow-writing-to-package-directory generate-feature Contratos --api
swift package --allow-writing-to-package-directory generate-feature MisCasos --api --local --module
swift package --allow-writing-to-package-directory generate-feature Standalone --no-register
```

`--path`/`--target` no tienen efecto en modo multi (no hay un target existente donde
elegir una subcarpeta: cada feature es su propio target, con su propia ruta fija).
`--service-from`/`--store-from` combinan con modo multi para la Logic, pero con un límite
conocido: cada feature tiene su propio target de tests en modo multi, así que reutilizar
el mock de OTRO feature (p. ej. `ProductsServiceMock`) desde `DetailFeatureTests` solo
compila si ese mock es visible entre targets de test distintos — el generador lo avisa en
los pasos siguientes en vez de fingir que funciona igual que en modo no-multi (un único
target de tests, donde siempre es visible).

Fuera de modo multi, `generate-feature` se comporta exactamente igual que siempre — el
`.archinit-multi` es lo único que activa este modo, y su ausencia lo deja todo sin cambios.

### `archinit`

```bash
swift package --allow-writing-to-package-directory archinit
```

Inicializa un proyecto consumidor de una sola vez: crea `.archlint.yml`, `Features/`,
copia `AGENTS.md` a la raíz del proyecto, añade (o crea) `CLAUDE.md` con una línea
`@AGENTS.md`, e instala `.claude/skills/feature.md` (el skill `/feature` de Claude Code,
que explica el generador y recuerda las reglas del linter). Nunca sobrescribe un fichero
que ya exista.

## Ver también

- <doc:Lint> — la parte que obliga: un error de build, no un README que se puede ignorar.
- <doc:Architecture> — las reglas y las cuatro variantes que el generador produce.
