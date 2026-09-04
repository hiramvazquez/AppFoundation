// Adoptar la maqueta de la app sin tocar el paquete: los cuatro estilos de ScreenContainer
// se sustituyen por Environment (como ButtonStyle), una vez en la raíz; una pantalla puede
// cambiar el suyo por debajo. El paquete decide CUÁNDO se muestra cada estado; la app, CÓMO.
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
