# AppFoundation

Base para apps SwiftUI nuevas: estado de pantalla, navegación, inyección de dependencias,
shell de UI, y la arquitectura View → ViewModel → Logic → Services/Stores con un generador
y un linter que la hacen cumplir.

## Requisitos

Swift 6.2+ (swift-tools 6.2) · iOS 17+ / macOS 14+ · sin dependencias externas.

## Instalación

```swift
// Package.swift
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
```

Para desarrollo local: `.package(path: "../AppFoundation")`.

## Empieza aquí

La documentación completa vive en DocC (Xcode: **Product ▸ Build Documentation**, o
`AppFoundation/Sources/AppFoundation/Documentation.docc/`): landing, guía de 20 minutos,
un artículo por pieza, arquitectura, recetas, testing y el generador/linter.

Seis pasos mínimos:

```swift
import AppFoundation

// 1. Composition root
struct GreetingModule: DependencyModule {
    func register(in container: Container) {
        container.register(GreetingServicing.self) { _ in GreetingService() }
    }
}
Container.shared.register(modules: [GreetingModule()])

// 2. Logic — la regla de negocio, sin SwiftUI
final class GreetingLogic: GreetingLogicProtocol {
    func greeting(for name: String) -> String { "Hola, \(name)" }
}

// 3. ViewModel — orquesta, nunca conoce Service/Store
final class GreetingViewModel: LogicViewModel<any GreetingLogicProtocol>, ActionHandling {
    private(set) var message = ""
    enum Action: Sendable { case load(name: String) }
    func handle(_ action: Action) {
        switch action { case .load(let name): load(name: name) }
    }
    private func load(name: String) {
        performLoad { vm in vm.message = vm.logic.greeting(for: name) }
    }
}

// 4. View — cáscara con ScreenContainer
struct GreetingView: View {
    let viewModel: GreetingViewModel
    var body: some View {
        ScreenContainer(viewModel) { send in
            Text(viewModel.message).onAppear { send(.load(name: "Hiram")) }
        }
    }
}
```

El generador escribe este mismo cascarón (View/ViewModel/Logic/Service/Store + tests) en
segundos: `swift package --allow-writing-to-package-directory generate-feature Login --api`.

## Más

- [`AGENTS.md`](AGENTS.md) — arquitectura, naming y qué NO hacer, para agentes y humanos.
- [`Examples/`](Examples/) — cuatro apps completas, una por variante.
- [`CHANGELOG.md`](CHANGELOG.md) — cambios por versión.

## Licencia

MIT — ver [LICENSE](../LICENSE) en la raíz del repositorio.
