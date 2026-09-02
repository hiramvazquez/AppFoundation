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

let package = Package(
    name: "MiApp",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MiApp", targets: ["MiApp"])],
    dependencies: [
        .package(url: "https://github.com/hiram0816/spm-pro.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "MiApp",
            dependencies: [.product(name: "AppFoundation", package: "spm-pro")]
        ),
        .testTarget(
            name: "MiAppTests",
            dependencies: [
                "MiApp",
                .product(name: "AppFoundationTestSupport", package: "spm-pro")
            ]
        )
    ]
)
```

**Resultado esperado**: `swift build` resuelve el paquete y compila sin errores (el target
`MiApp` aún no tiene ficheros — créalos en el paso 4).

### 2. Registrar dependencias

`Container` es el composition root: el único sitio que conoce tipos concretos.

@Snippet(path: "AppFoundation/Snippets/getting-started-container")

**Resultado esperado**: `print` imprime `Hola, Hiram`.

### 3. Definir rutas y el coordinador

`Coordinator` modela una pila de navegación con una sola capa modal.

@Snippet(path: "AppFoundation/Snippets/getting-started-coordinator")

**Resultado esperado**: `RootView` compila; `CoordinatorView` resuelve `.home` y
`.greeting(name:)` sin código de navegación adicional.

### 4. Construir un ViewModel con Logic

Un feature real separa la regla de negocio (`Logic`) de la orquestación de pantalla
(`ViewModel`) desde el primer momento — ver <doc:Architecture> para las cuatro variantes.

@Snippet(path: "AppFoundation/Snippets/getting-started-viewmodel")

**Resultado esperado**: tras `handle(.load(name:))`, `viewModel.phase == .content` y
`viewModel.message == "Hola, Hiram"`.

### 5. Renderizar con `ScreenContainer`

@Snippet(path: "AppFoundation/Snippets/getting-started-view")

**Resultado esperado**: `GreetingView` compila; al aparecer, `send(.load(name:))` dispara
`performLoad`, la pantalla muestra el indicador de carga y luego el texto.

### 6. Testear

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
