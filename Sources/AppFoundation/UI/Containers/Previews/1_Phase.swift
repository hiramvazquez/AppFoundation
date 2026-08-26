#if canImport(SwiftUI) && DEBUG
import SwiftUI

/// Previews para cada estado de ViewPhase + LoadingStyle.
struct ScreenContainer_Phase_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 1 · Idle
            ScreenContainer(
                phase: .constant(.idle),
                navigation: .title("Idle", style: .solid)
            ) {
                VStack {
                    Spacer()
                    Text("Sin datos todavía").foregroundColor(.secondary)
                    Spacer()
                }
            }
            .previewDisplayName("idle")

            // 2 · Content
            ScreenContainer(
                phase: .constant(.content),
                navigation: .title("Content", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("content")

            // 3 · Loading fullScreen
            ScreenContainer(
                phase: .constant(.loading),
                loadingStyle: .constant(.fullScreen),
                navigation: .title("Loading", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("loading · fullScreen")

            // 4 · Loading inline
            ScreenContainer(
                phase: .constant(.loading),
                loadingStyle: .constant(.inline),
                navigation: .title("Loading", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("loading · inline")

            // 5 · Loading overlay
            ScreenContainer(
                phase: .constant(.loading),
                loadingStyle: .constant(.overlay),
                navigation: .title("Loading", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("loading · overlay")
        }
        .frame(width: 390, height: 700)

        Group {
            // 6 · Empty
            ScreenContainer(
                phase: .constant(.empty),
                navigation: .title("Empty", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("empty")

            // 7 · Error con retry
            ScreenContainer(
                phase: .constant(.error(ScreenError(
                    title: "Sin conexión",
                    message: "Comprueba tu conexión e inténtalo de nuevo.",
                    retry: {}
                ))),
                navigation: .title("Error", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("error · con retry")

            // 8 · Error sin retry
            ScreenContainer(
                phase: .constant(.error(ScreenError(
                    title: "Sin permiso",
                    message: "No tienes acceso a este contenido."
                ))),
                navigation: .title("Error", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("error · sin retry")
        }
        .frame(width: 390, height: 700)
    }
}

#endif
