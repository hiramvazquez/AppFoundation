# Empezando

Una app SwiftUI mínima sobre AppFoundation, de cero a tests en verde, en seis pasos.

## Paso 0: `archinit` (una vez por proyecto)

```bash
swift package --allow-writing-to-package-directory archinit
```

Crea `.archlint.yml`, `Features/`, `AGENTS.md`, la línea `@AGENTS.md` en `CLAUDE.md` y la
skill `.claude/skills/feature.md`. Es lo que hace que un agente de IA que trabaje en el
proyecto conozca la arquitectura y use `generate-feature` en vez de improvisar; el
paquete en sí queda en `DerivedData`/`.build/checkouts`, fuera de lo que un agente lee.

## Overview

Cada paso deja el paquete compilando. El resultado esperado se indica al final de cada
uno; si algo no compila, revisa ese paso antes de seguir.

### 1. Instalar el paquete

Crea un paquete SwiftPM (o añade el target a uno existente) y declara la dependencia:

```swift
// Package.swift
// swift-tools-version: 6.2
import PackageDescription

// Mismo defaultIsolation/upcoming features que AppFoundation (ver su Package.swift): sin
// esto, un tipo MainActor-isolated de AppFoundation (BaseViewModel, LogicViewModel,
// Container) no se puede usar desde una función normal sin marcarla @MainActor a mano.
let swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

let package = Package(
    name: "MiApp",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MiApp", targets: ["MiApp"])],
    dependencies: [
        // Cada paquete se publica en su propio repositorio (subtree split); sustituye la URL por la real.
    .package(url: "https://github.com/hiramvazquez/AppFoundation.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "MiApp",
            dependencies: [.product(name: "AppFoundation", package: "AppFoundation")],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "MiAppTests",
            dependencies: [
                "MiApp",
                .product(name: "AppFoundationTestSupport", package: "AppFoundation")
            ],
            swiftSettings: swiftSettings
        )
    ]
)
```

**Resultado esperado**: `swift build` resuelve el paquete y compila sin errores (el target
`MiApp` aún no tiene ficheros — créalos en el paso 4).

### 2. Registrar dependencias

`Container` es el composition root: el único sitio que conoce tipos concretos. Copia esto
en un fichero nuevo, `Sources/MiApp/GreetingModule.swift`:

<!-- snippet: getting-started-container -->
```swift
import AppFoundation

protocol GreetingServicing {
    func greeting(for name: String) -> String
}

struct GreetingService: GreetingServicing {
    func greeting(for name: String) -> String { "Hola, \(name)" }
}

struct GreetingModule: DependencyModule {
    func register(in container: Container) {
        container.register(GreetingServicing.self) { _ in GreetingService() }
    }
}

Container.shared.register(modules: [GreetingModule()])
let service: GreetingServicing = Container.shared.resolve()
let greeting = service.greeting(for: "Hiram")  // "Hola, Hiram"
```

**Resultado esperado**: compila. Las últimas tres líneas del snippet son la demostración de
uso — en un target de biblioteca (no un ejecutable) no van sueltas en el fichero; muévelas
a un test (`Container.shared.register(modules: [GreetingModule()])` en el `setUp` de tu
suite, o directamente en el paso 6) o al `init` de tu `App`.

### 3. Definir rutas y el coordinador

`Coordinator` modela una pila de navegación con una sola capa modal. Nuevo fichero,
`Sources/MiApp/RootView.swift`:

<!-- snippet: getting-started-coordinator -->
```swift
import AppFoundation
import SwiftUI

enum AppRoute: Hashable {
    case home
    case greeting(name: String)
}

struct RootView: View {
    @State private var coordinator = Coordinator<AppRoute>(root: .home)

    var body: some View {
        CoordinatorView(coordinator: coordinator) { route in
            switch route {
            case .home:
                Text("Home")
            case .greeting(let name):
                Text("Hola, \(name)")
            }
        }
    }
}
```

**Resultado esperado**: `RootView` compila; `CoordinatorView` resuelve `.home` y
`.greeting(name:)` sin código de navegación adicional.

### 4. Construir un ViewModel con Logic

Un feature real separa la regla de negocio (`Logic`) de la orquestación de pantalla
(`ViewModel`) desde el primer momento — ver <doc:Architecture> para las cuatro variantes.
Nuevo fichero, `Sources/MiApp/GreetingFeature.swift`:

<!-- snippet: getting-started-viewmodel -->
```swift
import AppFoundation
import Observation

protocol GreetingLogicProtocol: Logic {
    func greeting(for name: String) -> String
}

final class GreetingLogic: GreetingLogicProtocol {
    func greeting(for name: String) -> String {
        "Hola, \(name)"
    }
}

@Observable
final class GreetingViewModel: LogicViewModel<any GreetingLogicProtocol>, ActionHandling {
    // Nonisolated on purpose: without an explicit deinit the compiler synthesizes an isolated
    // one that goes through a back-deploy shim on older OS versions (see AppFoundation's
    // `docs/repros/isolated-deinit-backdeploy.md`). Nothing to clean up here.
    deinit {}

    private(set) var message: String = ""

    enum Action: Sendable {
        case load(name: String)
    }

    func handle(_ action: Action) {
        switch action {
        case .load(let name): load(name: name)
        }
    }

    private func load(name: String) {
        performLoad { vm in
            vm.message = vm.logic.greeting(for: name)
        }
    }
}

let viewModel = GreetingViewModel(logic: GreetingLogic())
viewModel.handle(.load(name: "Hiram"))
```

**Resultado esperado**: compila (las dos últimas líneas del snippet, la demostración de
uso, van al paso 6 — un test, no el fichero de biblioteca). Tras `handle(.load(name:))`,
`viewModel.phase == .content` y `viewModel.message == "Hola, Hiram"`.

### 5. Renderizar con `ScreenContainer`

El snippet de abajo repite `GreetingLogicProtocol`/`GreetingLogic`/`GreetingViewModel` del
paso 4 para poder compilar solo, como todo snippet de esta documentación — en tu proyecto
ya los tienes en `GreetingFeature.swift`: copia solo el `struct GreetingView` en un
fichero nuevo, `Sources/MiApp/GreetingView.swift`.

<!-- snippet: getting-started-view -->
```swift
import AppFoundation
import SwiftUI

protocol GreetingLogicProtocol: Logic {
    func greeting(for name: String) -> String
}

final class GreetingLogic: GreetingLogicProtocol {
    func greeting(for name: String) -> String {
        "Hola, \(name)"
    }
}

@Observable
final class GreetingViewModel: LogicViewModel<any GreetingLogicProtocol>, ActionHandling {
    // Nonisolated on purpose: without an explicit deinit the compiler synthesizes an isolated
    // one that goes through a back-deploy shim on older OS versions (see AppFoundation's
    // `docs/repros/isolated-deinit-backdeploy.md`). Nothing to clean up here.
    deinit {}

    private(set) var message: String = ""

    enum Action: Sendable {
        case load(name: String)
    }

    func handle(_ action: Action) {
        switch action {
        case .load(let name): load(name: name)
        }
    }

    private func load(name: String) {
        performLoad { vm in
            vm.message = vm.logic.greeting(for: name)
        }
    }
}

struct GreetingView: View {
    // El composition root construye el view model; la vista lo RETIENE con `@State`
    // (con `let`, SwiftUI puede sustituir la instancia que recibió `.load` al reejecutar
    // este init durante un push, y la que queda en pantalla nunca carga).
    @State private var viewModel: GreetingViewModel

    init(viewModel: GreetingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScreenContainer(viewModel) { send in
            Text(viewModel.message)
                .task { send(.load(name: "Hiram")) }
        }
        .navigationTitle("Saludo")
    }
}
```

**Resultado esperado**: `GreetingView` compila; al aparecer, `send(.load(name:))` dispara
`performLoad`, la pantalla muestra el indicador de carga y luego el texto.

### 6. Testear

`Tests/MiAppTests/GreetingFeatureTests.swift`:

```swift
import Testing

@testable import MiApp

@Test func loadShowsGreeting() async {
    let viewModel = GreetingViewModel(logic: GreetingLogic())

    viewModel.handle(.load(name: "Hiram"))
    await viewModel.inFlightLoad?.value

    #expect(viewModel.phase == .content)
    #expect(viewModel.message == "Hola, Hiram")
}
```

**Resultado esperado**: `swift test` compila y corre 1 test, en verde. `inFlightLoad`
evita sondear `phase` en un bucle — ver <doc:Testing>.

## Desde un proyecto Xcode

Lo de arriba asume un paquete SwiftPM puro. Un proyecto Xcode real (xcodegen, o cualquier
otro generador de `.xcodeproj`) tiene fricciones adicionales — las nueve de abajo son las
que encontró integrar este kit en
[AppStarter](https://github.com/hiramvazquez/AppStarter) (app real sobre DummyJSON,
`docs/INFORME-INTEGRACION.md` de ese repo tiene el detalle completo con trazas). Cada
punto: el síntoma, la solución, el fragmento mínimo.

### 1. El generador y el linter necesitan un `Package.swift`

**Síntoma**: `generate-feature`/`archinit`/`archlint` son *command plugins* de SwiftPM —
un `.xcodeproj` de xcodegen, por sí solo, no tiene ningún `Package.swift` sobre el que
corran. **Solución**: paquete local con TODAS las features (`AppStarterKit/`, con su
propio `Package.swift`, dependiendo de AppFoundation/CoreNetworking por URL exactamente
como cualquier consumidor) + un target de app cáscara (xcodegen) que solo tiene `@main`,
la vista raíz y la composición de `DependencyModule`s.

```yaml
# project.yml (xcodegen), simplificado
packages:
  MiAppKit:
    path: MiAppKit
targets:
  MiApp:
    type: application
    sources: [MiApp]
    dependencies:
      - package: MiAppKit
        product: MiAppKit
```

### 2. Xcode exige aprobar el plugin antes de compilar

**Síntoma**: el primer build falla con `Validate plug-in "ArchitectureLint" in package
"appfoundation"` — Xcode pide confiar en el plugin con un diálogo interactivo, que no
existe en CI. **Solución**: `-skipPackagePluginValidation` en cada invocación no
interactiva de `xcodebuild`; en Xcode, aprobarlo una vez desde el diálogo.

```bash
xcodebuild -scheme MiApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -skipPackagePluginValidation test
```

### 3. Un target no hereda productos de una dependencia DE una dependencia

**Síntoma**: el target de la app enlaza solo el paquete local (`MiAppKit`), pero si algún
fichero de la app (`MiAppApp.swift`, un fixture offline) hace `import AppFoundation` o
`import CoreNetworkingTestSupport` directamente, `xcodebuild test` (no `build`) falla en el
linker con `Undefined symbol`. **Solución**: declarar también `AppFoundation`/
`CoreNetworking` como paquetes del target de la app en `project.yml`, con la MISMA URL y
versión que `MiAppKit/Package.swift` ya fija — SwiftPM deduplica por identidad de paquete,
no descarga un segundo checkout.

```yaml
packages:
  AppFoundation:
    url: https://github.com/hiramvazquez/AppFoundation.git
    from: 1.0.0
targets:
  MiApp:
    dependencies:
      - package: MiAppKit
        product: MiAppKit
      - package: AppFoundation
        product: AppFoundation
```

### 4. xcodegen no referencia el test target de un paquete local desde un scheme

**Síntoma**: añadir el test target del paquete local (`MiAppKitTests`) a la acción `test`
de un scheme xcodegen falla con `Spec validation error: ... invalid test target`.
**Solución**: correrlo aparte — `swift test` dentro del paquete local, como un paso
distinto de `xcodebuild test` (que cubre solo los test targets nativos de Xcode) — en
local y en CI.

```bash
xcodebuild -scheme MiApp -destination '...' -skipPackagePluginValidation test
cd MiAppKit && swift test
```

### 5. `.accessibilityIdentifier` en un contenedor pisa el de sus hijos

**Síntoma**: un `.accessibilityIdentifier` en un `VStack`/contenedor se propaga a TODOS
sus hijos en el árbol de accesibilidad — incluso a uno que ya tiene su propio identificador
explícito, que queda pisado. **Solución**: poner `.accessibilityIdentifier` solo en las
hojas (`Text`, `Button`), nunca en un contenedor que también tiene hijos identificados.

### 6. Variables de entorno de la shell no llegan al test runner de XCUITest

**Síntoma**: `MI_FLAG=1 xcodebuild test`, leída con `ProcessInfo.processInfo.environment`
dentro del target de XCUITests, funciona de forma intermitente — el proceso del test
runner que el simulador lanza no es un hijo directo de `xcodebuild` y no hereda de forma
fiable el entorno de la shell que invocó el comando. **Solución**: hornear la variable en
el `.xcscheme` vía la interpolación de xcodegen (que lee el entorno en el momento de
`xcodegen generate`, un proceso síncrono normal — sí fiable), no leerla del entorno en
tiempo de test. `XCTestConfigurationFilePath`, en cambio, SÍ llega de forma fiable al
entorno del PROCESO DE LA APP bajo prueba (no al del test runner) — útil para que la app
detecte "estoy corriendo bajo XCUITest" sin depender de una variable horneada (punto 7).

```yaml
schemes:
  MiApp:
    test:
      environmentVariables:
        MI_FLAG: "${MI_FLAG}"
```

### 7. El diálogo "¿Guardar contraseña?" interrumpe los XCUITests en un momento impredecible

**Síntoma**: tras el primer envío exitoso de un formulario con `SecureField`, el simulador
puede ofrecer guardar la contraseña en cualquier momento — un `Sheet` del sistema que
bloquea cualquier tap posterior sin que `XCUIElement.tap()` reporte más que "not
hittable". **Solución de dos capas**: la View desactiva `.textContentType(.password)`
cuando detecta `XCTestConfigurationFilePath` en el entorno (punto 6); como red de
seguridad, cada ayudante de navegación de los XCUITests comprueba y descarta el diálogo
(`"Ahora no"`/`"Not Now"`) antes y durante cada espera, no solo una vez tras el login.

```swift
SecureField("Contraseña", text: $password)
    .textContentType(isRunningUITests ? nil : .password)

private var isRunningUITests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
```

### 8. XCUITests sin red: `InMemoryTransport` con fixtures registrados antes del primer request

**Síntoma**: unos XCUITests que dependen de la API real son lentos y frágiles en CI.
**Solución**: un modo offline (`-UITestOffline` en `launchArguments`) que construye la app
con `InMemoryTransport` (`CoreNetworkingTestSupport`) y registra cada respuesta ANTES de
que `RootView` renderice y salga el primer request — el `init()` de una `App` SwiftUI no
puede ser `async`, así que registrar (una `actor`, `async`) necesita puentearse a síncrono
en ese punto (un `DispatchSemaphore` alrededor de un `Task`, ver
`AppStarter/OfflineFixtures.swift`).

### 9. El runner de CI arranca con un Xcode cuyo `swift-tools` es menor que 6.2

**Síntoma**: `macos-15` en GitHub Actions no siempre trae seleccionado por defecto el
Xcode más reciente disponible en la imagen — `swift-tools-version: 6.2` de este paquete
no resuelve. **Solución**: seleccionar explícitamente el Xcode más nuevo instalado antes
de cualquier paso que use `xcodebuild`/`swift`.

```yaml
- name: Select the newest available Xcode (swift-tools 6.2 mínimo)
  run: |
    LATEST=$(ls -d /Applications/Xcode_*.app 2>/dev/null | sort -V | tail -n 1)
    sudo xcode-select -s "${LATEST:-/Applications/Xcode.app}"
    xcodebuild -version
```

El `.github/workflows/ci.yml` completo de AppStarter tiene los tres jobs (lint + unit,
`xcodebuild test`, integración real) con estos nueve puntos aplicados.

## App grande: tres niveles en un comando

Para una app con varios equipos o muchas features, `archinit --multi` deja la estructura
modular por targets (cáscara + `Packages/Platform` + `Packages/Features`) con las reglas de
dependencia vigiladas por el linter: <doc:MultiModule>.

## De aquí en adelante

- Una Logic que depende de una API o de datos locales: <doc:Architecture>.
- Errores propios y mapeo a copy de pantalla: <doc:ErrorHandling>.
- Generar este mismo cascarón con un comando: <doc:Generator>.
