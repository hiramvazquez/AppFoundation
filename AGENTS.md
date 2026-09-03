# AppFoundation — guía para agentes

Arquitectura obligatoria de cualquier feature: **View → ViewModel → Logic → Services/Stores**.
Un `Logic` por `ViewModel`. Todo entra por `init`, siempre como protocolo. Nada de esto
llama a `Container.shared`/`@Inject` por su cuenta: el composition root es el `XxxModule`.

## Si estás en un proyecto que consume este paquete

Ejecuta una vez `swift package --allow-writing-to-package-directory archinit` en la raíz
del proyecto: copia este fichero como `AGENTS.md`, crea `.archlint.yml` y `Features/`, añade
`@AGENTS.md` a `CLAUDE.md` e instala la skill `/feature`. A partir de ahí, crea features
con `generate-feature` (abajo) y deja que `ArchitectureLint` valide el build.

## Capas

- **View** (SwiftUI): recibe el `ViewModel`, renderiza con `ScreenContainer(vm) { send in … }`.
  Nunca importa `CoreNetworking`, nunca referencia `*Logic`/`*Service`/`*Store`. El
  composition root lo construye; la View lo retiene con `@State private var viewModel:
  XxxViewModel` + `_viewModel = State(initialValue: viewModel)` en el `init` — nunca `let
  viewModel:`. SwiftUI reejecuta el builder del destino de navegación durante un push; con
  `let` esa reejecución sustituye la instancia que ya recibió `.load` (vía `.task`), esa
  instancia se libera (`performLoad` captura `[weak self]`, sin error) y la que queda en
  pantalla nunca lo recibe — pantalla vacía sin spinner ni error. En DEBUG, `ActionSender`
  y `performLoad`/`performActivity` registran en `os_log` (subsystem `AppFoundation`) cada
  acción descartada porque su ViewModel ya no existe, configurable vía
  `AppFoundationDiagnostics`; `ArchitectureLint` (R12) avisa de `let viewModel:` en un
  `*View.swift`.
- **ViewModel** (`@MainActor`): `final class XxxViewModel: LogicViewModel<any XxxLogicProtocol>,
  ActionHandling`. Orquesta: recibe `Action` en `handle(_:)`, llama a `logic`, actualiza
  `phase`/estado propio, decide navegación (`Router`/`Coordinator`). Nunca conoce
  `APIService`, `URLSession`, SwiftData ni un `*Service`/`*Store` concreto — solo `logic`.
- **Logic** (`nonisolated`, métodos `async`): `protocol XxxLogicProtocol: Logic { … }` +
  `final class XxxLogic: XxxLogicProtocol`. TODA la lógica de negocio; traduce el error del
  Service/Store (`APIError`, SwiftData) a un error de dominio propio (`XxxError: DomainError`)
  ANTES de devolverlo — el ViewModel y el `ErrorPresenting` nunca ven `APIError`. Sin
  `import SwiftUI`/`UIKit`. Sin referencias a `*ViewModel`/`Router`/`Coordinator`.
  Dependencias por `init` como `any XxxServicing`/`any XxxStoring`.
- **Service** (API, `struct Sendable`): `protocol XxxServicing: Sendable` + una
  implementación que es la ÚNICA que toca `APIServiceProtocol`/`BaseRequest` y que devuelve
  MODELOS DE DOMINIO (nunca el DTO/`Response` decodificado). Un Service = una llamada a API
  con su propio `BaseRequest`. Conformar `EndpointService` (`CoreNetworking`) da `call(_:)`
  gratis.
- **Store** (local, `actor`/`@ModelActor` con SwiftData): `protocol XxxStoring` + una
  implementación que es la ÚNICA que toca SwiftData/CoreData/UserDefaults/Keychain/
  FileManager, y que igualmente devuelve modelos de dominio. Misma forma que un Service,
  distinto origen. Un `actor` que recibe por `init` un valor no-`Sendable`
  (`UserDefaults`, `FileManager`, un cliente de Keychain) y conforma inline a su
  `XxxStoring: Sendable` no compila bajo `defaultIsolation(MainActor)` — declara la
  conformidad en una `extension` (o inyecta un valor `Sendable`):

  ```swift
  // No compila: conformidad inline + propiedad no-Sendable asignada en el init.
  actor UserDefaultsSettingsStore: SettingsStoring {
      private let defaults: UserDefaults
      init(defaults: UserDefaults = .standard) { self.defaults = defaults }   // error
  }

  // Compila: la conformidad va en una extension separada.
  actor UserDefaultsSettingsStore {
      private let defaults: UserDefaults
      init(defaults: UserDefaults = .standard) { self.defaults = defaults }
  }
  extension UserDefaultsSettingsStore: SettingsStoring {}
  ```

  Repro completo, error exacto del compilador y todas las variantes probadas en
  `docs/repros/actor-inline-conformance.md`; ejemplo real en `Examples/NotesApp`
  (`Stores/NotesSettingsStore.swift`).

## Las cuatro variantes (mismas reglas)

| Variante | `Logic` depende de | Ejemplo |
|---|---|---|
| Solo API | `any XxxServicing` | `Examples/LoginApp` (+ `SessionStore`, logout global) |
| Solo local | `any XxxStoring` | `Examples/NotesApp` (SwiftData) |
| API + local | ambos (`cached()` + `refresh()`, cache-then-network) | `Examples/CatalogApp` |
| Sin datos | nada | `Examples/CounterApp` |

## Piezas de este paquete

- `Logic` (`Architecture/Logic/Logic.swift`): marcador `protocol Logic: AnyObject {}`.
- `DomainError` (`Architecture/AppError/DomainError.swift`): `protocol DomainError: Error,
  AppErrorConvertible, Sendable { var isRetryable: Bool { get } }` (default `false`) — lo
  que un `Logic` lanza en vez de propagar el error de su Service/Store.
- `LogicViewModel<L>` (`Architecture/ViewModels/LogicViewModel.swift`): `open class
  LogicViewModel<L>: BaseViewModel` con `public let logic: L`. NO conforma `ActionHandling`
  — cada subclase declara su propio `enum Action` y `handle(_:)`.
- `AppFoundationTestSupport` (producto SEPARADO, nunca en el binario de producción):
  `InMemoryStore<Key, Value>` (actor genérico para dobles de `*Storing`), `ManualClock`,
  `SpyRecorder<Call>`.

## Cómo testear cada capa

- **ViewModel**: `XxxLogicMock: XxxLogicProtocol` (spy) → `viewModel.handle(.acción)` →
  `await viewModel.inFlightLoad?.value` → assert sobre `phase`/propiedades observables.
- **Logic**: `XxxServiceMock`/`XxxStoreMock` (o `InMemoryStore`) → llama al método del
  `Logic` directamente; incluye un test por cada mapeo de error a `DomainError`.
- **Service**: `MockAPIService` (stub por tipo de request) para el caso feliz/error, e
  `InMemoryTransport` para el pipeline real (retries, interceptores, refresh de token).
- **Store**: `InMemoryStore`/`InMemoryXxxStore` en tests; SwiftData con `ModelContainer`
  en memoria (`isStoredInMemoryOnly: true`) solo en el test del Store real.

## Qué NO hacer

- No uses `try!`, `as!`, `x!`, `T!` ni `[unowned self]`: SwiftLint (`.swiftlint.yml`, instalado
  por `archinit`) los convierte en error de build. Una excepción se justifica en el sitio con
  `// swiftlint:disable:next <regla>` y el motivo en el comentario, nunca bajando el umbral.

- No inyectes un tipo concreto de Service/Store/Logic en otra capa — siempre `any XxxProtocol`.
- No dejes que `APIError`/un error de SwiftData llegue al ViewModel: mapéalo a `DomainError`
  dentro del `Logic`.
- No pongas lógica de negocio ni navegación en el `ViewModel`/`Logic` respectivamente.
- No llames a `Container.shared`/`@Inject` desde ViewModel/Logic/Service/Store: regístralos
  y resuélvelos desde el `XxxModule` (composition root).

## Generador y linter

No escribas una feature a mano si `generate-feature` puede darte el cascarón correcto
desde el primer segundo:

```bash
swift package --allow-writing-to-package-directory generate-feature Login --api      # Service
swift package --allow-writing-to-package-directory generate-feature Notes --local    # Store (SwiftData)
swift package --allow-writing-to-package-directory generate-feature Catalog --api --local
swift package --allow-writing-to-package-directory generate-feature Counter          # sin datos
```

Genera View/ViewModel/Logic/Service/Store/Module + tests/mocks, todo compilando y en
verde. Nunca edita el `.xcodeproj` ni el `enum AppRoute` — imprime esos dos pasos
manuales al terminar; hazlos tú.

`SwiftLint` es la segunda capa (calidad: tamaños, complejidad, idioms, forzados). `archinit`
deja `.swiftlint.yml`; el plugin `SwiftLintBuildToolPlugin` se añade al target junto a
`ArchitectureLint` (artículo `CodeQuality`). Los `error` rompen el build; los `warning` solo
bloquean en CI con `--strict`.

`ArchitectureLint` (build-tool plugin, se añade al target en `Package.swift`) y
`swift package archlint` (command plugin, para CI o una comprobación puntual) aplican
las reglas R1-R11 — un error de build es lo único que no se puede ignorar. Antes de
escribir código de una capa a mano, repasa la tabla de reglas en el artículo `Lint` de
`Documentation.docc`: importar `CoreNetworking` fuera de Logic/Service (R1/R7), dejar
que un `APIError`/DTO llegue al ViewModel (R7/R8), o llamar a `Container.shared` fuera
del `XxxModule` (R10) hacen fallar el build, no solo el code review.

## Definition of Done

Nada está terminado hasta que estos comandos se han EJECUTADO y su salida real aparece
en el informe. «Compila» o «en verde» sin la salida pegada no cuenta; ha ocurrido más de
una vez que un agente reportó 0 errores sin haber medido y había cientos.

En un proyecto que consume este paquete (desde la raíz del paquete local, p. ej.
`AppStarterKit/`):

```bash
swift build                                      # compila, y con ello corre ArchitectureLint (R1-R12)
swift test                                       # unitarios por capa: ViewModel, Logic, Service, Store
swift package archlint                           # comprobación explícita; debe imprimir "0 errors"
swiftlint lint --strict Sources Tests            # calidad (brew install swiftlint); sin salida = limpio
# Si el proyecto tiene app de Xcode y XCUITests:
xcodebuild test -scheme <App> -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation
```

Reglas del informe:

1. Pega la ÚLTIMA línea de cada comando (`Test run with N tests … passed`, `archlint: 0
   errors`, `** TEST SUCCEEDED **`). Si un comando no se ejecutó, dilo y explica por qué.
2. Un test que se saltó, un warning que se silenció o un `--path`/`-only-testing` que
   reduce el alcance se declara explícitamente.
3. Cada feature nueva trae su test por capa (ver «Cómo testear cada capa»); una feature
   sin tests no está terminada aunque compile.
4. Si un fallo se diagnostica por lectura de código sin reproducirlo (trazas, test que
   falla), el informe lo marca como hipótesis, no como causa confirmada.

Al desarrollar el propio paquete (contribuciones a AppFoundation), la lista es la del CI:

```bash
swift format lint --strict --recursive Sources Tests Examples Plugins Snippets
SWIFT_STRICT_WARNINGS=1 swift build --build-tests
swift test --parallel
for e in CounterApp NotesApp LoginApp CatalogApp; do (cd Examples/$e && swift test); done
Scripts/check-doc-snippets.sh
Scripts/verify-generator.sh
xcodebuild build -scheme AppFoundation -destination 'generic/platform=iOS Simulator' -quiet
xcodebuild docbuild -scheme AppFoundation -destination 'generic/platform=iOS Simulator' -derivedDataPath "$(mktemp -d)"   # sin "warning:"
```

Ver también: [Examples/](Examples/) (los cuatro ejemplos de variante, código de referencia),
`README.md` (instalación y los seis pasos mínimos), `Sources/AppFoundation/Documentation.docc/`
(Xcode: **Product ▸ Build Documentation**) para la referencia completa por pieza, con
ejemplos que compilan (`Snippets/`), y [AppStarter](https://github.com/hiramvazquez/AppStarter)
— app real sobre DummyJSON con ambos paquetes, plantilla de arranque.

Los ejemplos de DocC están sincronizados con `Snippets/` por CI (`Scripts/check-doc-snippets.sh`, job `docs`).
