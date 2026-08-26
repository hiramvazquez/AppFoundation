#if canImport(SwiftUI) && DEBUG
import SwiftUI

/// Previews para custom view builders: loadingView, errorView, emptyView, alertView, bannerView.
struct ScreenContainer_CustomLoading_Previews: PreviewProvider {
    static var previews: some View {
        ScreenContainer(
            phase: .constant(.loading),
            navigation: .title("Custom loading", style: .solid)
        ) {
            PreviewSampleList()
        }
        .loadingView {
            VStack(spacing: 16) {
                ProgressView().progressViewStyle(.circular).controlSize(.large).tint(.accentColor)
                Text("Cargando datos…").font(.subheadline).foregroundColor(.secondary)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .frame(width: 390, height: 700)
        .previewDisplayName("custom · loadingView")
    }
}

struct ScreenContainer_CustomError_Previews: PreviewProvider {
    static var previews: some View {
        ScreenContainer(
            phase: .constant(.error(ScreenError(title: "¡Ups!", message: "Algo fue mal.", retry: {}))),
            navigation: .title("Custom error", style: .solid)
        ) {
            PreviewSampleList()
        }
        .errorView { error in
            VStack(spacing: 20) {
                Image(systemName: "wifi.slash").font(.system(size: 56)).foregroundColor(.red.opacity(0.8))
                Text(error.title).font(.title2.weight(.bold))
                Text(error.message).font(.body).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
                if let retry = error.retry {
                    Button(action: retry) { Label("Reintentar", systemImage: "arrow.clockwise") }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
        }
        .frame(width: 390, height: 700)
        .previewDisplayName("custom · errorView")
    }
}

struct ScreenContainer_CustomEmpty_Previews: PreviewProvider {
    static var previews: some View {
        ScreenContainer(
            phase: .constant(.empty),
            navigation: .title("Custom empty", style: .solid)
        ) {
            PreviewSampleList()
        }
        .emptyView {
            VStack(spacing: 16) {
                Image(systemName: "star.slash").font(.system(size: 48)).foregroundColor(.orange)
                Text("Sin favoritos aún").font(.title3.weight(.semibold))
                Text("Los ítems que guardes aparecerán aquí.").font(.subheadline).foregroundColor(.secondary)
                Button("Explorar") {}.buttonStyle(.bordered)
            }
        }
        .frame(width: 390, height: 700)
        .previewDisplayName("custom · emptyView")
    }
}

struct ScreenContainer_CustomAlertView_Previews: PreviewProvider {
    static var previews: some View {
        ScreenContainer(
            phase: .constant(.content),
            alert: .constant(.info(title: "Nuevo mensaje", message: "Tienes un mensaje nuevo.")),
            navigation: .title("Custom alert", style: .solid)
        ) {
            PreviewSampleList()
        }
        .alertView { alert in
            VStack(spacing: 12) {
                Image(systemName: "envelope.fill").font(.title).foregroundColor(.accentColor)
                Text(alert.title).font(.headline)
                Text(alert.message).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                Button(alert.primaryButton.title) { alert.primaryButton.action() }
                    .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 28))
        }
        .frame(width: 390, height: 700)
        .previewDisplayName("custom · alertView")
    }
}

struct ScreenContainer_CustomBannerView_Previews: PreviewProvider {
    static var previews: some View {
        ScreenContainer(
            phase: .constant(.content),
            banner: .constant(.success("Pago confirmado.")),
            navigation: .title("Custom banner", style: .solid)
        ) {
            PreviewSampleList()
        }
        .bannerView { banner in
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                Text(banner.message).font(.subheadline.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.platformBackground, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .frame(width: 390, height: 700)
        .previewDisplayName("custom · bannerView")
    }
}

#endif
