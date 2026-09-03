# UI

`ScreenContainer`, `ScreenChrome` y los `*ViewStyle` propagados por `Environment` — la
cáscara de una pantalla, sin `AnyView` en el call site.

## Overview

`ScreenContainer(_ state:chrome:content:)` renderiza `phase`/`activity`/`alert`/`banner`
automáticamente alrededor del contenido de la pantalla; solo requiere que `state` conforme
`ScreenState & ActionHandling` (`ScreenViewModel`) — nunca la clase concreta
`BaseViewModel`.

```swift
struct ProfileView: View {
    let viewModel: ProfileViewModel

    var body: some View {
        ScreenContainer(viewModel) { send in
            VStack {
                Text(viewModel.profile?.name ?? "—")
                Button("Actualizar") { send(.refresh) }
            }
            .onAppear { send(.load) }
        }
        .navigationTitle("Perfil")
    }
}
```

`viewModel.profile` se lee directamente del view model — `ScreenState` y cualquier estado
propio de la pantalla son válidos para renderizar; solo *actuar* sobre la pantalla pasa por
`send`.

Una pantalla de solo lectura (sin `ActionHandling`) usa `ScreenContainer(observing:)` o el
modifier `.screen(_:chrome:)` — sin `ActionSender` en `content`, porque no hay nada que
enviar.

### `ScreenChrome`: la barra nativa por defecto

`.native` (por defecto) nunca oculta la barra del sistema — la pantalla la controla con
`navigationTitle`/`toolbar`/`searchable`, y el swipe-back interactivo sigue funcionando
gratis. `.custom(NavigationBarConfiguration, placement:)` es opt-in explícito, solo cuando
la barra nativa genuinamente no puede hacer el trabajo (un header con avatar y saludo);
`ScreenContainer` instala `PopGestureEnabler` automáticamente en ese caso, pero verifica el
swipe-back a mano en simulador — no lo cubre un test unitario:

```swift
ScreenContainer(
    viewModel,
    chrome: .custom(.withBack(title: "Perfil") { /* … */ })
) { send in
    ProfileContent()
}
```

### Estilos por `Environment`, sin `AnyView`

`LoadingViewStyle`/`ErrorViewStyle`/`EmptyViewStyle`/`BannerViewStyle` siguen el mismo
patrón que `ButtonStyle`/`ProgressViewStyle` de SwiftUI:

<!-- snippet: ui-custom-error-style -->
```swift
import AppFoundation
import SwiftUI

struct BrandErrorStyle: ErrorViewStyle {
    func makeBody(configuration: ErrorConfiguration) -> some View {
        VStack(spacing: 12) {
            Text(configuration.error.title).font(.headline)
            Text(configuration.error.message)
            if let retry = configuration.error.retry {
                Button("Reintentar", action: retry)
            }
        }
        .padding()
    }
}

final class ProfileViewModel: BaseViewModel, ActionHandling {
    enum Action: Sendable { case load }
    func handle(_ action: Action) {}
}

struct ProfileScreen: View {
    @State private var viewModel: ProfileViewModel

    init(viewModel: ProfileViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScreenContainer(viewModel) { _ in Text("Perfil") }
            .errorViewStyle(BrandErrorStyle())
    }
}
```

`ScreenContainer(observing:)`/`.screen(_:chrome:)` construyen su estado por dentro con
`BindingBackedState`/`ObservingScreenState`: ambos llevan `@Observable` como documentación
(no tienen nada que instrumentar — cada propiedad reenvía a un `Binding` o a un
`ScreenState` envuelto, nunca es un stored property propio) y no se instancian a mano
fuera de esos dos puntos de entrada.

`ErasedView` (`AnyView` con otro nombre) es el ÚNICO punto de type-erasure del paquete,
usado solo en las piezas opt-in de la barra `.custom` (`NavigationBarItemContent.view`,
`NavigationBarTitle.custom`, contenido accesorio) — con `.native` por defecto, no entra en
juego.

## Topics

### Cáscara de pantalla

- ``ScreenContainer``
- ``ScreenChrome``
- ``PhaseView``
- ``BindingBackedState``
- ``ObservingScreenState``

### Estilos

- ``LoadingViewStyle``
- ``ErrorViewStyle``
- ``EmptyViewStyle``
- ``BannerViewStyle``

### Barra de navegación (opt-in)

- ``CustomNavigationBar``
- ``NavigationBarItem``
- ``NavigationBarConfiguration``
- ``NavigationBarStyle``
- ``ErasedView``
