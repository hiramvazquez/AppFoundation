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
print(service.greeting(for: "Hiram"))
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

protocol GreetingLogicProtocol: Logic {
    func greeting(for name: String) -> String
}

final class GreetingLogic: GreetingLogicProtocol {
    func greeting(for name: String) -> String {
        "Hola, \(name)"
    }
}

final class GreetingViewModel: LogicViewModel<any GreetingLogicProtocol>, ActionHandling {
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

final class GreetingViewModel: LogicViewModel<any GreetingLogicProtocol>, ActionHandling {
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

## De aquí en adelante

- Una Logic que depende de una API o de datos locales: <doc:Architecture>.
- Errores propios y mapeo a copy de pantalla: <doc:ErrorHandling>.
- Generar este mismo cascarón con un comando: <doc:Generator>.
