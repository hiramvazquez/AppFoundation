#if canImport(SwiftUI) && DEBUG
import SwiftUI

/// Previews para estilos custom: `LoadingViewStyle`, `ErrorViewStyle`, `EmptyViewStyle`,
/// `BannerViewStyle` — instalados vía `Environment` (AF-15), sin type erasure en la vista que
/// los define ni en el call site.

private struct BrandLoadingStyle: LoadingViewStyle {
    func makeBody(configuration: LoadingConfiguration) -> some View {
        VStack(spacing: 16) {
            ProgressView().progressViewStyle(.circular).controlSize(.large).tint(.accentColor)
            Text("Cargando datos…").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

#Preview("Custom · loadingViewStyle") {
    ScreenContainer(
        phase: .constant(.loading(.fullScreen)),
        chrome: .custom(.title("Custom loading", style: .solid))
    ) {
        PreviewSampleList()
    }
    .loadingViewStyle(BrandLoadingStyle())
    .frame(width: 390, height: 700)
}

private struct BrandErrorStyle: ErrorViewStyle {
    func makeBody(configuration: ErrorConfiguration) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash").font(.system(size: 56)).foregroundStyle(.red.opacity(0.8))
            Text(configuration.error.title).font(.title2.weight(.bold))
            Text(configuration.error.message).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let retry = configuration.error.retry {
                Button(action: retry) { Label("Reintentar", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
    }
}

#Preview("Custom · errorViewStyle") {
    ScreenContainer(
        phase: .constant(.error(ScreenError(title: "¡Ups!", message: "Algo fue mal.", retry: {}))),
        chrome: .custom(.title("Custom error", style: .solid))
    ) {
        PreviewSampleList()
    }
    .errorViewStyle(BrandErrorStyle())
    .frame(width: 390, height: 700)
}

private struct BrandEmptyStyle: EmptyViewStyle {
    func makeBody(configuration: EmptyConfiguration) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "star.slash").font(.system(size: 48)).foregroundStyle(.orange)
            Text("Sin favoritos aún").font(.title3.weight(.semibold))
            Text("Los ítems que guardes aparecerán aquí.").font(.subheadline).foregroundStyle(.secondary)
            Button("Explorar") {}.buttonStyle(.bordered)
        }
    }
}

#Preview("Custom · emptyViewStyle") {
    ScreenContainer(
        phase: .constant(.empty),
        chrome: .custom(.title("Custom empty", style: .solid))
    ) {
        PreviewSampleList()
    }
    .emptyViewStyle(BrandEmptyStyle())
    .frame(width: 390, height: 700)
}

private struct BrandBannerStyle: BannerViewStyle {
    func makeBody(configuration: BannerConfiguration) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            Text(configuration.banner.message).font(.subheadline.weight(.medium))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.platformBackground, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .onTapGesture(perform: configuration.dismiss)
    }
}

#Preview("Custom · bannerViewStyle") {
    ScreenContainer(
        phase: .constant(.content),
        banner: .constant(.success("Pago confirmado.")),
        chrome: .custom(.title("Custom banner", style: .solid))
    ) {
        PreviewSampleList()
    }
    .bannerViewStyle(BrandBannerStyle())
    .frame(width: 390, height: 700)
}

#endif
