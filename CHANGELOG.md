# Changelog — AppFoundation

Todos los cambios notables de este paquete se documentan en este fichero. El formato sigue
[Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el versionado,
[SemVer](https://semver.org/lang/es/).

## [Unreleased]

## [1.2.2] - 2026-09-04

### Corregido

- **`deinit {}` explícito en toda clase `@MainActor` del kit** (`Coordinator`, `Container`, `Inject`,
  `LogicViewModel`, `ObservingScreenState`, `BindingBackedState`), en la plantilla del ViewModel, los
  ejemplos y los snippets. Bajo `defaultIsolation(MainActor)`, una clase sin `deinit` recibe uno
  AISLADO sintetizado que en sistemas anteriores al runtime del toolchain pasa por
  `swift_task_deinitOnExecutorMainActorBackDeploy`; dos anidados (un ViewModel liberando su
  `Coordinator`) abortaron con un double free de libmalloc en iOS 26.2 (CI de AppStarter, Xcode
  26.3). Repro y símbolos en `docs/repros/isolated-deinit-backdeploy.md`.

## [1.2.1] - 2026-09-04

### Corregido

- **`@Observable` no se hereda de `BaseViewModel`**: el macro instrumenta solo las propiedades
  declaradas en la clase que lo lleva, así que un ViewModel sin él nunca notificaba sus
  propiedades propias (la vista se refrescaba solo cuando cambiaba `phase`/`activity`, por
  coincidencia). Descubierto en AppStarter con un contador de renders y medido con
  `withObservationTracking` (`ObservationInheritanceTests`). La plantilla del ViewModel, los
  cuatro ejemplos, los snippets, los artículos, el README y `AGENTS.md` declaran ahora
  `@Observable` en cada ViewModel.

### Añadido

- **Regla R15** (error): una `class` cuyo nombre termina en `ViewModel` debe llevar
  `@Observable`.

## [1.2.0] - 2026-09-04

### Añadido

- **`archinit --multi`** (PRD-AF-10): deja en un comando la app modular de tres niveles por
  targets, no por manifiestos: cáscara (`App/` con `@main`, `RootView`, `AppModule` y
  `AppRoute` con markers), `Packages/Platform` (`Domain`, un `<Cap>Kit` por `--capability`,
  un `<Sdk>Adapters` por `--adapter`; `Firebase` con `AnalyticsTracking`/`CrashReporting` y
  un adapter que compila con y sin el SDK), `Packages/Features` (manifiesto con markers para
  el alta automática de targets), `.archlint.yml` raíz con `modules:`, `.swiftlint.yml`,
  `.swift-format`, `AGENTS.md` con la tabla de dependencias real, `project.yml`, `Scripts/
  bootstrap.sh`, `ci.yml` con matriz por paquete. Idempotente, `--dry-run`, `--no-xcodegen`.
  `Scripts/bootstrap-multi.sh <Name>` crea el manifiesto mínimo y lo invoca. Plantillas en
  `Templates/Multi/`; lógica testeable en `ArchInitSupport` (24 tests).
- **`generate-feature` en modo multi**: detecta `.archinit-multi` y los markers, genera
  `Sources/<Name>Feature` y `Tests/<Name>FeatureTests`, da de alta el target, su test target
  y el producto entre los markers (única edición de manifiesto que hace; `--no-register` la
  desactiva) y añade el módulo al composition root y el `case` a `AppRoute`. `--module` crea
  `<Name>FeatureCore` y `<Name>FeatureUI` como targets reales. Fuera del modo multi, sin cambios.
- **Regla R13 (error)**: aislamiento entre módulos. `.archlint.yml` gana `modules:` (anidado o
  plano `modules.<glob>.allowedImports`), con globs en nombres e imports; el módulo se deduce
  de `Sources/<Target>/` o del `--module` que pasa el build-tool plugin; la config raíz se
  busca subiendo directorios. Sin `modules:`, nada cambia.
- **Regla R14 (aviso)**: dependencia por `branch:`/`revision:` en `Package.swift` (solo en
  `swift package archlint`).
- `Scripts/verify-multi.sh` y job `multi` en CI: arranque, `archinit --multi`, dos features
  generadas, build y tests de ambos paquetes, `archlint` limpio, y la prueba negativa de un
  `import` entre features que rompe el build con `[ArchLint.R13]`.

### Documentación

- Artículo `MultiModule` (por qué targets y no paquetes, la tabla de dependencias, el
  arranque, migrar una app existente en cinco pasos, qué vigilar), sección en
  `GettingStarted`, README y `AGENTS.md`.
- Artículo `Theming` («Adopta tu maqueta»): cómo una app sustituye carga, error, vacío,
  banners y barra de navegación por su diseño vía `Environment`, sin tocar el paquete; la
  tabla de lo que el paquete garantiza frente a lo que la app decide; el orden de trabajo
  cuando llega la maqueta; y qué debe (y qué no) contener un `DesignSystem` sin diseño.
  Snippet `ui-brand-theme` con los cuatro estilos, verificado por CI. Enlazado desde el
  índice, `UserInterface` y el README.

## [1.1.0] - 2026-09-03

### Añadido

- **Calidad de código: SwiftLint curado, instalado por `archinit`.** `Templates/swiftlint.yml`
  (copiado como `.swiftlint.yml` si no existe): `only_rules` explícito, `error` para lo que
  esconde un crash o una fuga (`try!`, `as!`, `x!`, `T!`, `[unowned]`, delegate fuerte, `Task`
  con `throw` sin capturar, `@State` no privado…) y `warning` para tamaños, complejidad e
  idioms, con el porqué de cada regla y de las tres descartadas en la calibración. Dos reglas
  propias por regex (`print` en producción, `privacy: .public`). `archinit` imprime los dos
  pasos manuales (dependencia `SwiftLintPlugins` y el plugin junto a `ArchitectureLint`).
- Artículo `CodeQuality` en DocC (las tres capas, instalación, qué bloquea y qué avisa,
  excepciones, calibración); secciones en README, `AGENTS.md` (Qué NO hacer, Definition of
  Done) y el skill `/feature`.
- `Scripts/verify-generator.sh` pasa `swiftlint --strict` con la plantilla sobre el código
  generado y los cuatro ejemplos cuando `swiftlint` está en el PATH; job `quality` en CI sobre
  ejemplos y snippets.

- `SpyRecorder.isEmpty` en `AppFoundationTestSupport`: `#expect(await spy.isEmpty)` en vez de
  `count == 0`.

### Corregido

- Los ejemplos y snippets cumplen la configuración curada: `count == 0` → `isEmpty`,
  `UserDefaults(suiteName:)!` → `try #require`, `.data(using:)!` → `Data(_.utf8)`, un ternario
  con `Void` → `if/else`, y el snippet de arranque ya no usa `print`.

## [1.0.2] - 2026-09-03

### Documentación

- Sección «Definition of Done» en `AGENTS.md` (y por tanto en el `AGENTS.md` que
  `archinit` copia a cada proyecto): los comandos exactos que hay que ejecutar y cuya
  última línea hay que pegar antes de dar algo por terminado, tanto en un proyecto
  consumidor (`swift build`, `swift test`, `swift package archlint`, `xcodebuild test`)
  como al contribuir al paquete (la lista del CI). Nace de la experiencia con agentes
  que reportaban «en verde» sin haber medido.

## [1.0.1] - 2026-09-03

Versión de mantenimiento a partir de las fricciones de la app de referencia
[AppStarter](https://github.com/hiramvazquez/AppStarter). Sin roturas de API.

### Corregido

- **La View es dueña de su ViewModel con `@State`.** `Templates/View.swift.txt`, los cuatro
  ejemplos y los snippets pasan de `let viewModel` a `@State private var viewModel` +
  `_viewModel = State(initialValue:)`, y de `.onAppear` a `.task` para la carga inicial.
  Con `let`, un ViewModel transitorio construido en el builder de destino de navegación
  se sustituía cuando SwiftUI reejecutaba el builder durante el push: la instancia que
  recibió `.load` moría, `performLoad` (`[weak self]`) no hacía nada y la que quedaba en
  pantalla nunca recibía la acción (pantalla vacía, sin spinner ni error).
- **`archlint` ya no entra nunca en `.build`, `.swiftpm`, `DerivedData` ni el directorio
  del VCS**: una lista fija `alwaysIgnore` se aplica siempre, aunque el `.archlint.yml`
  traiga un `ignore:` explícito (que sigue reemplazando solo los defaults de usuario).
  Antes, `swift package archlint` sin `--path` en un proyecto consumidor analizaba
  `.build/checkouts`, incluidos los fixtures «malos» del propio paquete.

### Añadido

- **Ninguna acción se pierde en silencio** (solo `DEBUG`, coste cero en release):
  `ActionSender` y `performLoad`/`performActivity` registran por `os_log` (subsystem
  `AppFoundation`, category `ActionSender`, nivel `.error`) toda acción o trabajo
  descartado porque el ViewModel ya fue liberado. `AppFoundationDiagnostics` expone
  `assertOnDroppedAction` (default `false`) y `droppedActionHandler` para tests.
  `ViewModelOwnershipTests` cubre ambos casos.
- **Regla R12 del linter** (severidad aviso): `let`/`var viewModel:` sin `@State` en un
  `*View.swift`.
- **`generate-feature --no-service` / `--no-store` / `--service-from <Feature>` /
  `--store-from <Feature>`**: una feature puede reutilizar el `Servicing`/`Storing` de
  otra ya generada (la Logic lo recibe por protocolo, el Module lo resuelve del contenedor,
  los tests reutilizan su mock) o dejar un placeholder con `// TODO`, sin generar un
  Service/Store nuevo. `Scripts/verify-generator.sh` cubre `Products --api` +
  `Detail --api --service-from Products`.
- `Examples/NotesApp`: `UserDefaultsNotesSettingsStore`, un `actor` sobre `UserDefaults`
  con la conformidad a su protocolo en una `extension` (ver Documentación), con tests.

### Documentación

- Regla «el composition root construye el ViewModel; la View lo retiene con `@State`» en
  `AGENTS.md`, `Architecture.md` y `FAQ.md`.
- Guía de actores con dependencias no-Sendable: bajo `defaultIsolation(MainActor)`, un
  `actor` con una propiedad almacenada no-Sendable asignada en el `init` y conformidad
  inline a su protocolo no compila; declarar la conformidad en una `extension` sí.
  Repro mínimo con el error exacto en `docs/repros/actor-inline-conformance.md`.
- Nueva sección «Desde un proyecto Xcode» en `GettingStarted.md`: paquete local + app
  cáscara con xcodegen, `-skipPackagePluginValidation`, productos transitivos, test targets
  de paquetes locales, `.accessibilityIdentifier` solo en hojas, variables de entorno
  horneadas en el scheme para XCUITest, `.textContentType(.password)` bajo XCUITest,
  modo offline con `InMemoryTransport` y selección de Xcode en CI.
- Sección «App de referencia» en el README (y en el de CoreNetworking) enlazando a
  AppStarter; R12 y las nuevas opciones del generador en `Lint.md` y `Generator.md`.

- Los 16 `@Snippet(path:)` de `Documentation.docc/` (no se resolvían en el primer
  `xcodebuild docbuild` sobre DerivedData limpio) se sustituyen por bloques de código en
  línea marcados `<!-- snippet: <name> -->`, verificados contra `Snippets/` por
  `Scripts/check-doc-snippets.sh` en CI (job `docs`, antes de `docbuild`).

## [1.0.0] - 2026-09-02

Primera versión estable.

### Roturas de API

- `performLoad`/`performActivity` ya no aceptan `() async throws -> Void`; `work` es
  `@MainActor (Self) async throws -> Void` — migrar `performLoad { self.foo() }` a
  `performLoad { vm in vm.foo() }`.
- `WrappedError.init` gana `now: () -> Date` y usa `#fileID` en vez de `#file` como
  default de `file`.
- `Container` pasa a `@MainActor` — se elimina el `NSLock` y el `@unchecked Sendable`.
- `register(_:lifecycle:factory:)` recibe ahora el `Container` en la fábrica.
- `Lifecycle.scoped(key:)`, `Container.createScope`/`destroyScope` desaparecen — usar
  `Container(parent:)`.
- `ContainerConcurrencyTests.swift` desaparece (sin objeto que probar en un `Container`
  `@MainActor`).
- `Debouncer`/`Throttler` pasan de `actor` a `@MainActor final class`, dejan de ser
  genéricos sobre `Clock` (`Debouncer<C>` → `Debouncer`) y `debounce(_:)` pasa a
  síncrono.
- `Debouncer.init(milliseconds:)` se elimina — usar `.milliseconds(n)`.
- `AppEnvironment` pasa de `struct` a `enum` namespace.
- `AppEnvironment.isTestOrPreview` se elimina (heurística de test en producción).
- `AppEnvironment.debugInfo` / `AppEnvironment.printDebugInfo()` se eliminan.
- `ScreenContainer`: el parámetro `navigation:` desaparece en favor de
  `chrome: ScreenChrome` (`.native` por defecto, `.custom(...)` opt-in).
- `.loadingView { }`, `.errorView { }`, `.emptyView { }`, `.bannerView { }` de
  `ScreenContainer` se eliminan en favor de `LoadingViewStyle`/`ErrorViewStyle`/
  `EmptyViewStyle`/`BannerViewStyle` propagados por `Environment`.
- `.alertView(builder:)` se elimina.
- `NavigationBarItemContent.view`, `NavigationBarTitle.custom` y las propiedades
  `accessoryView`/`customContent` de `NavigationBarConfiguration` dejan de exponer
  `AnyView` en su firma pública.
- `NavigationBarTitle.largeText` se elimina.
- `BannerState.duration` cambia de `BannerState.Duration` (enum propio) a
  `Swift.Duration?`.
- `Coordinator.navigationHistory` pasa a `internal` (antes `public` solo en `DEBUG`).
- `ScreenContainer.init(viewModel: BaseViewModel, ...)` se elimina. `ScreenContainer` pasa
  a `ScreenContainer<State: ScreenViewModel, Content: View>` (`ScreenViewModel` =
  `ScreenState & ActionHandling`, ambos protocolos nuevos): ya no depende de la clase
  concreta `BaseViewModel`, solo del contrato mínimo. El nuevo init designado es
  `ScreenContainer(_ state:chrome:backgroundColor:content:)`, con `content` recibiendo un
  `ActionSender<State.Action>` en vez de nada — la vista ya no puede llamar métodos del
  view model directamente, solo `send(.load)`. Los init de conveniencia (`title:`,
  `onBack:`, `searchText:`) migran del mismo modo (`viewModel:` → `_ state:`, `content`
  recibe el sender). Migrar `ScreenContainer(viewModel: vm) { ... }` a
  `ScreenContainer(vm) { send in ... }`, y hacer que `vm` conforme `ActionHandling` (un
  `enum Action`, `func handle(_ action: Action)`) para poder pasarlo.

### Added

- `ScreenState` (`Architecture/State/ScreenState.swift`): el contrato mínimo que
  `ScreenContainer` observa (`phase`/`activity` de solo lectura, `alert`/`banner`
  `{ get set }`). `BaseViewModel` conforma (`extension BaseViewModel: ScreenState {}`) sin
  ganar ningún método nuevo — la obligación de `handle(_:)` la impone `ScreenContainer`, no
  `BaseViewModel`.
- `ActionHandling` (`Architecture/Actions/ActionHandling.swift`): protocolo con
  `associatedtype Action: Sendable` y `func handle(_ action: Action)` — el único punto de
  entrada de las acciones de usuario de una pantalla, testeable con `vm.handle(.load)` sin
  exponer métodos `private`.
- `ActionSender<Action>`: lo único que el closure de contenido de `ScreenContainer` recibe
  para actuar sobre la pantalla (`send(.load)`/`sender(.load)`); se construye vía
  `ActionHandling.sender`, capturando el view model **débilmente** (`[weak self]`) — un
  `ActionSender` retenido no mantiene vivo al view model.
- `ScreenViewModel` — `typealias ScreenViewModel = ScreenState & ActionHandling`.
- `ScreenContainer(observing:chrome:backgroundColor:content:)`: init para pantallas de solo
  lectura (`ScreenState` sin `ActionHandling`) — sin `ActionSender` en `content`.
- `.screen(_:chrome:)`: modifier equivalente a `ScreenContainer(observing:)` para envolver
  una vista existente con la cáscara de una pantalla de solo lectura.
- `PhaseView.init(observing:backgroundColor:content:)`: variante de `PhaseView` que observa
  un `some ScreenState` directamente, sin `Binding<ViewPhase>`.
- `Logic` (`Architecture/Logic/Logic.swift`): `public protocol Logic: AnyObject {}`, el
  marcador que toda `XxxLogicProtocol` de una feature conforma — sin requisitos propios;
  documenta la arquitectura View → ViewModel → Logic → Services/Stores en el propio tipo.
- `LogicViewModel<L>` (`Architecture/ViewModels/LogicViewModel.swift`): `open class
  LogicViewModel<L>: BaseViewModel` con `public let logic: L` e `init(logic:errorPresenter:
  cancellationRecognizer:clock:)`. Hereda `phase`/`activity`/`performLoad`/`performActivity`
  de `BaseViewModel`; no conforma `ActionHandling` (cada subclase declara su propio
  `enum Action`).
- Nuevo producto **`AppFoundationTestSupport`** (target separado; nunca en el binario de
  producción, nunca dependencia del producto `AppFoundation`): `InMemoryStore<Key: Hashable
  & Sendable, Value: Sendable>` (actor genérico para dobles de `*Storing`), `ManualClock`
  (mismo contrato que el de `CoreNetworkingTestSupport`, duplicado — AppFoundation no
  depende de CoreNetworking), `SpyRecorder<Call: Sendable>` (grabador de llamadas thread-safe
  para spies generados/hechos a mano).
- `DomainError` (`Architecture/AppError/DomainError.swift`): `public protocol DomainError:
  Error, AppErrorConvertible, Sendable { var isRetryable: Bool { get } }` (default
  `isRetryable = false`) — lo que un `Logic` lanza en vez de propagar el error de su
  Service/Store; el `ViewModel`/`ErrorPresenting` de una app nunca vuelven a ver un
  `APIError` o un error de SwiftData.
- `AGENTS.md` en la raíz del paquete: arquitectura, naming, las cuatro variantes y cómo
  testear cada capa.
- `Examples/`: cuatro paquetes SwiftPM autocontenidos, uno por variante — `CounterApp`
  (sin datos), `NotesApp` (solo local, SwiftData real vía `@ModelActor`), `LoginApp` (solo
  API; `SessionStore` + logout global cuando falla el refresh del token), `CatalogApp`
  (API + local; `CatalogLogic.cached()`/`.refresh()` explícitos, cache-then-network).
- `archlint` (`executableTarget`, sin dependencias externas): analizador léxico propio
  (tokens, `import`, declaraciones `class/struct/enum/actor/protocol`, ignora comentarios y
  strings) que aplica las reglas R1-R11 y emite diagnósticos
  `ruta:línea:col: error: [ArchLint.Rn] mensaje` navegables en Xcode. Configuración opcional
  `.archlint.yml` (formato propio `key: value` + listas, sin librería YAML): sufijos por
  capa, `strict:`, `disabled:`, `ignore:`. Código dentro de `#if DEBUG`/`#Preview { … }`
  queda exento.
- **`ArchitectureLint`**: build-tool plugin — `plugins: [.plugin(name: "ArchitectureLint",
  package: "AppFoundation")]` en un target — corre `archlint` sobre `target.sourceFiles` en
  cada build; una violación falla el build. **`ArchLintCommand`**: el mismo `archlint` como
  command plugin, `swift package archlint [--path DIR]`, para CI sin integrarlo en ningún
  target.
- **`GenerateFeature`**: command plugin, `swift package --allow-writing-to-package-directory
  generate-feature <Nombre> [--api] [--local] [--module] [--analytics] [--no-logic]
  [--no-tests] [--path Features] [--dry-run] [--target NAME] [--route AppRoute.xxx]`. Genera
  el cascarón View → ViewModel → Logic → Services/Stores (+ tests/mocks) desde plantillas de
  texto en `AppFoundation/Templates/*.txt` (motor de plantillas propio, `{{Feature}}`/
  `{{feature}}` y bloques `{{#flag}}…{{/flag}}`/`{{^flag}}…{{/flag}}`, sin librería externa).
  Nunca edita el `.xcodeproj` ni el `enum AppRoute` — los imprime como pasos manuales.
- **`ArchInit`**: command plugin, `swift package --allow-writing-to-package-directory
  archinit`. Crea `.archlint.yml`, `Features/`, copia `AGENTS.md` a la raíz del proyecto,
  añade (o crea) `CLAUDE.md` con `@AGENTS.md`, e instala `.claude/skills/feature.md` (skill
  `/feature` de Claude Code). Nunca sobrescribe un fichero existente.
- `Scripts/verify-generator.sh` (verificación de integración real en un paquete temporal
  fuera del repo, usado también por el job `generator` de CI).
- `BaseViewModel.inFlightLoad`/`inFlightActivity: Task<Void, Never>?` (`public
  private(set)`, `@ObservationIgnored`): el `Task` en vuelo de `performLoad`/`load(_:)` y
  `performActivity`/`activity(_:)` respectivamente, `nil` al terminar. Pensado para tests
  deterministas cuando la llamada pasa por `handle(_:)` (que devuelve `Void`):
  `viewModel.handle(.load); await viewModel.inFlightLoad?.value` en vez de sondear
  `phase`/`hasError` en un bucle con `Task.sleep`.
- `BaseViewModel.init(errorPresenter:cancellationRecognizer:clock:)` gana `cancellationRecognizer:`
  y `clock:` (ambos `nil` por defecto — no rompe llamadas existentes). Misma precedencia que
  `errorPresenter`: instancia > `BaseViewModel.cancellationRecognizer`/`BaseViewModel.clock`
  (los `static var`, que siguen existiendo para configuración a nivel de app).
- Documentación: `BindingBackedState`/`ObservingScreenState` (`ScreenContainer.swift`)
  documentan por qué observan correctamente sin que `@Observable` (con el que ahora se
  marcan, sin efecto: ninguna de sus propiedades es almacenada) haga ningún trabajo.
  `ErasedView` documenta sus cuatro usos restantes, todos en la barra de navegación
  `.custom`, opt-in.
- `Examples/IntegrationExample` (sustituido más tarde por `Examples/LoginApp`) ganó
  `ProfileView`/`ProfilePreview`: la vista SwiftUI que integra `ScreenContainer` con
  `ProfileViewModel`, con una preview sobre `MockAPIService` y un estilo de error instalado
  por `Environment`.
- `LoadableViewModel`, adoptado por `BaseViewModel`: `performLoad`/`performActivity` (y las
  variantes estructuradas `load`/`activity`) entregan el view model a `work` como parámetro
  en vez de depender de la captura del closure — la forma de API que cierra el ciclo de
  retención en fase `.error` y hace que `deinit` cancele de verdad el trabajo en vuelo.
- `ErrorPresenting` / `DefaultErrorPresenter`: un único sitio, configurable por la app, que
  mapea errores a copy de `ScreenError` (`BaseViewModel.errorPresenter`, sobreescribible por
  instancia vía `BaseViewModel(errorPresenter:)`). Un error ajeno que no es
  `AppErrorConvertible` ni `LocalizedError` cae a un mensaje genérico localizado, nunca a
  `error.localizedDescription`.
- `CancellationRecognizing` / `DefaultCancellationRecognizer`: detección de cancelación
  extensible más allá de `CancellationError` tipado (por defecto también reconoce
  `URLError(.cancelled)`), configurable vía `BaseViewModel.cancellationRecognizer`.
- `L10n.genericErrorMessage` (EN + ES) — el copy de fallback que `DefaultErrorPresenter`
  muestra para errores que no puede presentar de otro modo.
- `AppFoundationLogger.errors` — loguea el detalle técnico de errores no presentables
  (`.private`), nunca mostrado en pantalla.
- `BaseViewModel.clock` (`any Clock<Duration>` inyectable, por defecto `ContinuousClock()`):
  el temporizador de auto-dismiss del banner ya no duerme de verdad en tests.
- Detección de ciclos de dependencias (A → B → A) en las fábricas de `Container`:
  `preconditionFailure` con un mensaje que nombra todos los tipos implicados.
- `ScreenChrome`: `.native` (la barra del sistema nunca se oculta; la pantalla la controla
  con `navigationTitle`/`toolbar`/`searchable`) y `.custom(NavigationBarConfiguration,
  placement:)`.
- `PopGestureEnabler` (`UI/Platform`, solo `iOS`): reinstala el gesto interactivo de
  swipe-back que `UINavigationController` desactiva al ocultar la barra nativa;
  `ScreenContainer` lo instala automáticamente cuando `chrome` es `.custom`.
- `LoadingViewStyle` / `ErrorViewStyle` / `EmptyViewStyle` / `BannerViewStyle` y sus
  implementaciones por defecto, con el mismo patrón que `ButtonStyle`/`ProgressViewStyle`
  de SwiftUI.

### Fixed

- **Crítico**: un `BaseViewModel` en fase `.error` nunca se liberaba cuando `work` capturaba
  `self` (el patrón documentado): `phase → ScreenError.retry → work → self` formaba un
  ciclo de referencia permanente. Cerrado por la nueva forma de API de `LoadableViewModel`.
- `deinit` ahora cancela de verdad un `performLoad`/`performActivity` en vuelo: como `work`
  ya no captura el view model, soltar la última referencia externa permite que se libere, y
  su `deinit` cancela el `Task` propio.
- La barra nativa ya no se oculta en todas las rutas, lo que restaura el gesto de
  swipe-back para cualquier pantalla en `chrome: .native`.
- `CustomNavigationBar` ya no se instancia dos veces en el árbol (contenido + overlay de
  estado): el chrome se instala una única vez alrededor de todo el screen.
- Altura de `CustomNavigationBar` con `@ScaledMetric` en vez de un valor fijo de 44pt;
  iconos con fuentes semánticas en vez de tamaños fijos (Dynamic Type).
- APIs deprecadas: `.edgesIgnoringSafeArea` → `.ignoresSafeArea(.container, edges:)`,
  `.foregroundColor` → `.foregroundStyle`, `.cornerRadius(_:)` →
  `.clipShape(.rect(cornerRadius:))`, `PreviewProvider` → `#Preview`.
- `Background.swift` se renombra a `PhaseView.swift` para que el fichero coincida con el
  tipo que contiene.

### Changed

- `WrappedError` conforma `CustomDebugStringConvertible` (antes una propiedad
  `debugDescription` a secas); su conformidad `Equatable` se documenta como una
  comparación de `context` + `code` + `underlying.localizedDescription`, no una
  comparación estructural de `underlying`.
