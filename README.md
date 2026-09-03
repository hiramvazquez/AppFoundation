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
    // Cada paquete se publica en su propio repositorio (subtree split); sustituye la URL por la real.
    .package(url: "https://github.com/hiramvazquez/AppFoundation.git", from: "1.0.0")
],
targets: [
    .target(
        name: "MiApp",
        dependencies: [.product(name: "AppFoundation", package: "AppFoundation")]
    ),
    .testTarget(
        name: "MiAppTests",
        dependencies: [
            "MiApp",
            .product(name: "AppFoundationTestSupport", package: "AppFoundation")
        ]
    )
]
```

Para desarrollo local: `.package(path: "../AppFoundation")`.

## Empieza aquí

**Paso 0, una sola vez por proyecto** (también para los agentes de IA que trabajen en él):

```bash
swift package --allow-writing-to-package-directory archinit
```

Deja en la raíz del proyecto `.archlint.yml`, `Features/`, `AGENTS.md` (la arquitectura que
generador y linter hacen cumplir), una línea `@AGENTS.md` en `CLAUDE.md` y la skill
`.claude/skills/feature.md`. Sin esto, un agente no ve las reglas: el paquete vive en
`DerivedData`/`.build/checkouts`, fuera de lo que lee. Con esto, `/feature Login --api`
genera el módulo completo dentro de la arquitectura.


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

// 4. View — cáscara con ScreenContainer. El composition root construye el ViewModel; la
// View lo retiene con @State (nunca `let`, ver AGENTS.md, sección View).
struct GreetingView: View {
    @State private var viewModel: GreetingViewModel

    init(viewModel: GreetingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScreenContainer(viewModel) { send in
            Text(viewModel.message).onAppear { send(.load(name: "Hiram")) }
        }
    }
}
```

El generador escribe este mismo cascarón (View/ViewModel/Logic/Service/Store + tests) en
segundos: `swift package --allow-writing-to-package-directory generate-feature Login --api`.

## App de referencia

[AppStarter](https://github.com/hiramvazquez/AppStarter) — app real sobre DummyJSON:
login/refresh de token, lista paginada, detalle, favoritos con SwiftData, búsqueda;
XCUITests offline con fixtures registrados; plantilla de arranque (paquete local + app
cáscara de Xcode) lista para clonar. Ver el artículo `GettingStarted` de DocC, sección
«Desde un proyecto Xcode», para lo que ese repo enseñó sobre integrar este kit fuera de un
paquete SPM puro.

## Calidad de código

`archinit` deja también `.swiftlint.yml`, la configuración curada de SwiftLint (`only_rules`,
severidad y porqué de cada regla, calibrada contra código real): `ArchitectureLint` valida
DÓNDE está el código, SwiftLint CÓMO está escrito, el compilador la concurrencia. Añade el
plugin junto a `ArchitectureLint` y un `try!` rompe el build igual que una violación de capa;
en CI, `swiftlint --strict`. Artículo `CodeQuality` en DocC.

## Más

- [`AGENTS.md`](AGENTS.md) — arquitectura, naming y qué NO hacer, para agentes y humanos.
- [`Examples/`](Examples/) — cuatro apps completas, una por variante.
- [`CHANGELOG.md`](CHANGELOG.md) — cambios por versión.

## Licencia

MIT — ver [LICENSE](LICENSE).
