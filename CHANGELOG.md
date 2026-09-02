# Changelog — AppFoundation

Todos los cambios notables de este paquete se documentan en este fichero. El formato sigue
[Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el versionado,
[SemVer](https://semver.org/lang/es/).

## [Unreleased]

### Documentación

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
