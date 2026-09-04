# App modular de tres niveles

`archinit --multi` deja lista, en un comando, una app modular por **targets** y no por
manifiestos: cáscara de app, `Packages/Platform` (Domain, Kits, Adapters) y
`Packages/Features` (un target por feature), con el linter vigilando quién importa a quién.

## Overview

Modularizar una app con un paquete por feature es el error más común y el más caro: decenas
de `Package.swift` que Xcode evalúa en cada cambio de scheme, dependencias por rama que
consultan la red al resolver, SDKs pesados compilados desde fuente, y un `Core` del que
depende todo. El síntoma es conocido: minutos al cambiar de scheme y previews que nunca
funcionan. La alternativa es la misma modularidad con pocos manifiestos: la granularidad
va en los targets.

```
<repo>/
├── App/                      cáscara: @main, RootView, AppModule (composition root), AppRoute
├── AppTests/  AppUITests/    smoke del composition root + arranque offline
├── Packages/
│   ├── Platform/             1 Package.swift: Domain + <Cap>Kit por capacidad + <Sdk>Adapters por SDK
│   └── Features/             1 Package.swift: un target <Name>Feature por feature (+ sus tests)
├── project.yml · Scripts/bootstrap.sh · .github/workflows/ci.yml
└── .archlint.yml (módulos) · .swiftlint.yml · .swift-format · AGENTS.md · CLAUDE.md
```

Dos manifiestos locales, tres remotos (AppFoundation, CoreNetworking, el SDK que toque).
«Resolving package graph» tarda segundos, las previews de una feature compilan su módulo y
los kits, y tocar una feature no recompila las demás.

## Las reglas de dependencia

Se generan en el `.archlint.yml` de la raíz (sección `modules:`) y en la tabla de `AGENTS.md`
con los nombres reales del proyecto; `archlint` las aplica como regla R13 (<doc:Lint>):

| Módulo | Puede importar | Nunca importa |
|---|---|---|
| `Domain` | Foundation | nada más |
| `<Cap>Kit` (p. ej. `CameraKit`) | Domain + frameworks del sistema | features, adapters, SDKs |
| `<Sdk>Adapters` (p. ej. `FirebaseAdapters`) | Domain + el SDK | features |
| `<Name>Feature` | AppFoundation, CoreNetworking, Domain | otra feature, cualquier SDK, cualquier Kit |
| App | todo | lógica de negocio |

Las dos ideas que lo hacen funcionar:

- **Las features no se conocen.** `MisCasosFeature` no importa `IndemnizacionesFeature`. Si
  navega a una indemnización, lo hace por una ruta de `AppRoute` que resuelve la app; si
  necesita datos de otra feature, recibe un protocolo de `Domain` por `init`, y el composition
  root decide quién lo implementa.
- **Los SDKs y las capacidades del dispositivo entran por protocolo.** Ninguna feature importa
  Firebase ni AVFoundation: recibe `any AnalyticsTracking` o `any CameraCapturing`, definidos
  en `Domain` e implementados en `FirebaseAdapters`/`CameraKit`. En tests, un spy. Un `import
  FirebaseAnalytics` dentro de una feature es un error de build, no un comentario en el PR.

## Arranque

Un command plugin solo corre sobre un paquete que dependa de AppFoundation, así que en un
repo vacío hace falta un manifiesto mínimo antes de invocarlo. `Scripts/bootstrap-multi.sh`
(en el repositorio de AppFoundation) lo hace por ti:

```bash
mkdir MiApp && cd MiApp && git init
curl -fsSL https://raw.githubusercontent.com/hiramvazquez/AppFoundation/main/Scripts/bootstrap-multi.sh -o bootstrap-multi.sh
bash bootstrap-multi.sh MiApp --capability Camera --adapter Firebase
```

A mano son cinco líneas: `Packages/Features/Package.swift` con solo la dependencia de
AppFoundation, y desde ese directorio
`swift package --allow-writing-to-package-directory archinit --multi --root ../.. --name MiApp
--capability Camera --adapter Firebase`.

Opciones: `--root <dir>` (raíz del repo; por defecto el padre de `Packages/`), `--name`,
`--bundle-id`, `--capability <Cap>` (repetible: crea `<Cap>Kit` y su protocolo en Domain),
`--adapter <Sdk>` (repetible; `Firebase` trae la dependencia por tag, `AnalyticsTracking` y
`CrashReporting` en Domain y un adapter que compila con y sin el SDK resuelto),
`--no-xcodegen` (sin `project.yml`, `ci.yml` ni `bootstrap.sh`), `--dry-run`. Es idempotente:
nunca pisa un fichero existente e imprime el diff sugerido.

Después: `Scripts/bootstrap.sh` genera el `.xcodeproj` con xcodegen, y en `Packages/Features`
cada `generate-feature <Name> --api` crea el target, su test target y el producto entre los
markers del manifiesto, y añade el módulo al composition root y el `case` a `AppRoute`
(<doc:Generator>, «Modo multi»).

## Migrar una app existente

No hay comando de migración; el orden que funciona, sin parar el desarrollo:

1. `Packages/Platform` con `Domain`: mover ahí los modelos y protocolos que ya compartan dos
   módulos. Es la única extracción que cuesta.
2. `Packages/Features`: cada módulo actual entra como target tal cual está, uno por commit,
   con `public` donde haga falta. Sin refactorizar por dentro todavía.
3. `ArchitectureLint` target por target, primero con las reglas de capa en `disabled:` si hay
   mucho ruido, y R13 desde el primer día: es la que evita que la deuda crezca.
4. Features nuevas con `generate-feature`; las viejas se acercan a View → ViewModel → Logic →
   Services/Stores cuando se tocan, no antes.
5. Los adapters al final: cuando el último `import` del SDK salga de una feature.

## Qué vigilar para no volver al problema

- Contar manifiestos: dos locales es la norma; un tercero solo si aparece un `DesignSystem`.
- Nunca `branch:` ni `revision:` en un manifiesto (R14 avisa); `Package.resolved` versionado.
- Terceros pesados como binarios o detrás de un adapter, para que no se recompilen desde fuente.
- Macros propias solo si compensan de sobra: SwiftSyntax es un coste fijo de minutos.
- Schemes de paquetes ocultos; solo el de la app y los dos o tres que se usan.

## Ver también

- <doc:Lint> — R13 y R14, y el formato de `modules:`.
- <doc:Generator> — `generate-feature` en modo multi.
- <doc:GettingStarted> — el caso simple (cáscara + un paquete) y desde un proyecto Xcode.
