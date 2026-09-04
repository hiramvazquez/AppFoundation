# Adopta tu maqueta

Cómo una app sustituye las pantallas de carga, error, vacío, los banners y la barra de
navegación por su propio diseño, sin tocar el paquete y sin perder lo que el paquete garantiza.

## Overview

Casi ninguna app va a usar las pantallas genéricas del paquete tal cual: llega una maqueta y
todo cambia. Por eso ninguna de ellas es una vista fija. `ScreenContainer` pide cada estado a un
protocolo (`LoadingViewStyle`, `ErrorViewStyle`, `EmptyViewStyle`, `BannerViewStyle`) que viaja
por el `Environment`, igual que `ButtonStyle` o `ProgressViewStyle` en SwiftUI. El paquete trae
un `Default…` de cada uno; la app instala los suyos y el paquete sigue intacto.

La línea que separa lo que el paquete decide de lo que decide la app:

| El paquete garantiza (no se puede romper) | La app decide (sin tocar el paquete) |
|---|---|
| Cuándo se muestra cada estado (`ViewPhase`, `ActivityState`) | Cómo se ve cada estado |
| El reintento del error y la cancelación al salir | Colores, tipografía, iconos, animación |
| El anuncio de VoiceOver al llegar un banner y su autocierre | La forma del banner y dónde va el botón de cerrar |
| Que el contenido se oculta bajo un error o un vacío | Qué ilustración y qué texto llevan |
| Swipe-back con barra custom (`PopGestureEnabler`) | Fondo, colores, altura y items de la barra |

## Los cuatro estilos, una vez en la raíz

Un estilo es un `struct` con `makeBody(configuration:)`. La configuración trae lo que necesitas
para dibujar: el `ScreenError` (título, mensaje, `retry`), el `ActivityStyle` (`.fullScreen`,
`.inline`, `.overlay`), el `BannerState` (mensaje, `style` success/info/warning/error) con su
`dismiss`. Se instalan una vez, en la raíz, y todas las pantallas los heredan; una pantalla
concreta puede cambiar el suyo por debajo.

<!-- snippet: ui-brand-theme -->
```swift
import AppFoundation
import SwiftUI

// 1. Los valores de la maqueta, en un solo sitio (mañana, las variables de Figma).
enum Brand {
    static let accent = Color(red: 0.13, green: 0.55, blue: 0.45)
    static let surface = Color.gray.opacity(0.15)
    static let spacing: CGFloat = 16
}

// 2. Un estilo por estado, dibujado con esos valores.
struct BrandLoadingStyle: LoadingViewStyle {
    func makeBody(configuration: LoadingConfiguration) -> some View {
        switch configuration.style {
        case .fullScreen:
            ProgressView().tint(Brand.accent).scaleEffect(1.4)
        case .inline, .overlay:
            ProgressView().tint(Brand.accent)
        }
    }
}

struct BrandErrorStyle: ErrorViewStyle {
    func makeBody(configuration: ErrorConfiguration) -> some View {
        VStack(spacing: Brand.spacing) {
            Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(Brand.accent)
            Text(configuration.error.title).font(.title3.bold())
            Text(configuration.error.message).multilineTextAlignment(.center)
            if let retry = configuration.error.retry {
                Button("Reintentar", action: retry).buttonStyle(.borderedProminent).tint(Brand.accent)
            }
        }
        .padding(Brand.spacing)
    }
}

struct BrandEmptyStyle: EmptyViewStyle {
    func makeBody(configuration: EmptyConfiguration) -> some View {
        ContentUnavailableView(
            "Nada por aquí",
            systemImage: "tray",
            description: Text("Cuando haya datos, aparecerán en esta lista.")
        )
    }
}

struct BrandBannerStyle: BannerViewStyle {
    func makeBody(configuration: BannerConfiguration) -> some View {
        HStack {
            Text(configuration.banner.message)
            Spacer()
            Button("Cerrar", action: configuration.dismiss).font(.caption)
        }
        .padding(Brand.spacing)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Brand.spacing)
    }
}

// 3. Una vez, en la raíz: todas las pantallas lo heredan.
struct BrandRootView: View {
    var body: some View {
        Text("Tu CoordinatorView aquí")
            .loadingViewStyle(BrandLoadingStyle())
            .errorViewStyle(BrandErrorStyle())
            .emptyViewStyle(BrandEmptyStyle())
            .bannerViewStyle(BrandBannerStyle())
    }
}

// 4. Una pantalla concreta puede cambiar solo el suyo, por debajo de la raíz.
@Observable
final class OnboardingViewModel: BaseViewModel, ActionHandling {
    enum Action: Sendable { case load }
    func handle(_ action: Action) {}
}

struct OnboardingScreen: View {
    @State private var viewModel: OnboardingViewModel

    init(viewModel: OnboardingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScreenContainer(viewModel) { _ in Text("Bienvenido") }
            .errorViewStyle(BrandErrorStyle())  // o cualquier otro, solo para esta pantalla
    }
}
```

Sin `AnyView` en el sitio de uso: cada modificador es genérico sobre el estilo y el borrado de
tipo ocurre dentro del paquete (`ErasedView`), una sola vez.

## La barra de navegación

Con `chrome: .custom(configuration)`, la barra es `CustomNavigationBar` y su aspecto es un
`NavigationBarStyle` (valor, no protocolo): fondo `.solid(color)` o `.blur(material)`,
`titleColor`, `tintColor`, separador y altura, con presets `.default`, `.solid`, `.transparent`
y `.blur`. Define el de tu marca una vez y úsalo en cada `NavigationBarConfiguration`:

```swift
extension NavigationBarStyle {
    static let brand = NavigationBarStyle(
        background: .solid(Brand.surface),
        titleColor: .primary,
        tintColor: Brand.accent,
        showSeparator: true
    )
}
```

Si tu maqueta necesita una barra que `CustomNavigationBar` no puede dibujar (un título con
avatar, un fondo con degradado animado), no la fuerces: usa `chrome: .native` y tu barra como
parte del contenido, o `chrome: .custom(_, placement: .overlay)` para superponer la tuya.
`ScreenContainer` sigue gestionando estados, banners y swipe-back igual.

## Las alertas

Las alertas usan la presentación nativa a propósito: una alerta custom rompe la accesibilidad,
el foco de VoiceOver y las expectativas del sistema, y ninguna maqueta seria las rediseña. Si
algún día hace falta, será un `AlertViewStyle` más con el mismo patrón, no una modificación.

## Cuando llegue la maqueta: el orden de trabajo

1. **Valores primero.** Colores, espaciados y fuentes de Figma en un solo sitio (`enum Brand`
   en el ejemplo; con un `DesignSystem` serían tokens por `Environment`). Solo con eso, los
   estilos que dibujan con esos valores ya cambian.
2. **Un estilo por estado que difiera.** Escribe `BrandErrorStyle` solo si el error de la
   maqueta no es «icono + título + mensaje + botón»; si lo es, cambia los valores y basta.
3. **Una pantalla, un estilo distinto.** Onboarding sin banner, una lista con un vacío
   ilustrado: el modificador debajo de la raíz sobrescribe solo ahí.
4. **Lo que no encaje, fuera del paquete.** Un componente que no se parece en nada al del
   paquete se escribe en la feature o en el módulo de diseño de la app, y el del paquete no se
   usa. Nada de esto requiere un fork ni un cambio en AppFoundation.

## Y un DesignSystem, ¿hace falta?

Solo como contrato, nunca como diseño. Lo que merece la pena tener antes de la maqueta: los
tokens como protocolos (`ColorTokens`, `SpacingTokens`, `TypographyTokens`) con un tema
neutro por defecto, los cuatro estilos de arriba dibujados con esos tokens, y tres o cuatro
componentes de contrato (botón primario, campo con error, fila, tarjeta) con sus estados.
Cuando llegue la maqueta, la app entrega su `BrandTheme` y cubre la mayor parte; el resto
sigue el orden de trabajo anterior. Lo que no hay que meter sin maqueta: pantallas completas,
iconografía propia, animaciones de marca, porque habrá que tirarlas.

## Ver también

- <doc:UserInterface> — `ScreenContainer`, `ScreenChrome` y los estilos, pieza a pieza.
- <doc:Architecture> — por qué la View es una cáscara y de dónde salen los estados.
- <doc:Recipes> — pull-to-refresh, paginación y formularios sobre `ScreenContainer`.
