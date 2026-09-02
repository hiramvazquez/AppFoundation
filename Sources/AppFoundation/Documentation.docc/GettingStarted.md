# Empezando

Una app SwiftUI mínima sobre AppFoundation, de cero a tests en verde, en seis pasos.

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
    .package(url: "https://github.com/hiram0816/AppFoundation.git", from: "1.0.0")
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

@Snippet(path: "AppFoundation/Snippets/getting-started-container")

**Resultado esperado**: compila. Las últimas tres líneas del snippet son la demostración de
uso — en un target de biblioteca (no un ejecutable) no van sueltas en el fichero; muévelas
a un test (`Container.shared.register(modules: [GreetingModule()])` en el `setUp` de tu
suite, o directamente en el paso 6) o al `init` de tu `App`.

### 3. Definir rutas y el coordinador

`Coordinator` modela una pila de navegación con una sola capa modal. Nuevo fichero,
`Sources/MiApp/RootView.swift`:

@Snippet(path: "AppFoundation/Snippets/getting-started-coordinator")

**Resultado esperado**: `RootView` compila; `CoordinatorView` resuelve `.home` y
`.greeting(name:)` sin código de navegación adicional.

### 4. Construir un ViewModel con Logic

Un feature real separa la regla de negocio (`Logic`) de la orquestación de pantalla
(`ViewModel`) desde el primer momento — ver <doc:Architecture> para las cuatro variantes.
Nuevo fichero, `Sources/MiApp/GreetingFeature.swift`:

@Snippet(path: "AppFoundation/Snippets/getting-started-viewmodel")

**Resultado esperado**: compila (las dos últimas líneas del snippet, la demostración de
uso, van al paso 6 — un test, no el fichero de biblioteca). Tras `handle(.load(name:))`,
`viewModel.phase == .content` y `viewModel.message == "Hola, Hiram"`.

### 5. Renderizar con `ScreenContainer`

El snippet de abajo repite `GreetingLogicProtocol`/`GreetingLogic`/`GreetingViewModel` del
paso 4 para poder compilar solo, como todo snippet de esta documentación — en tu proyecto
ya los tienes en `GreetingFeature.swift`: copia solo el `struct GreetingView` en un
fichero nuevo, `Sources/MiApp/GreetingView.swift`.

@Snippet(path: "AppFoundation/Snippets/getting-started-view")

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
