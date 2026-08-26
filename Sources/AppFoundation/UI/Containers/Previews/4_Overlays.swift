#if canImport(SwiftUI) && DEBUG
import SwiftUI

/// Previews para ActivityState, AlertState y BannerState.
struct ScreenContainer_Activity_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 1 · Activity inline
            ScreenContainer(
                phase: .constant(.content),
                activity: .constant(.loading(.inline)),
                navigation: .title("Activity", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("activity · inline")

            // 2 · Activity overlay
            ScreenContainer(
                phase: .constant(.content),
                activity: .constant(.loading(.overlay)),
                navigation: .title("Activity", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("activity · overlay")

            // 3 · Alert info (1 botón)
            ScreenContainer(
                phase: .constant(.content),
                alert: .constant(.info(
                    title: "Actualización disponible",
                    message: "Hay una nueva versión. Actualiza para continuar."
                )),
                navigation: .title("Alert", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("alert · info")

            // 4 · Alert confirmation (2 botones)
            ScreenContainer(
                phase: .constant(.content),
                alert: .constant(.confirmation(
                    title: "¿Enviar reporte?",
                    message: "Se enviará al equipo de moderación.",
                    confirm: "Enviar",
                    cancel: "Cancelar",
                    onConfirm: {}
                )),
                navigation: .title("Alert", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("alert · confirmation")

            // 5 · Alert destructivo
            ScreenContainer(
                phase: .constant(.content),
                alert: .constant(.destructive(
                    title: "¿Eliminar cuenta?",
                    message: "Esta acción es irreversible. Se eliminará toda tu información.",
                    confirm: "Eliminar",
                    cancel: "Cancelar",
                    onConfirm: {}
                )),
                navigation: .title("Alert", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("alert · destructive")
        }
        .frame(width: 390, height: 700)

        Group {
            // 6 · Banner success
            ScreenContainer(
                phase: .constant(.content),
                banner: .constant(.success("Perfil actualizado correctamente.")),
                navigation: .title("Banner", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("banner · success")

            // 7 · Banner error
            ScreenContainer(
                phase: .constant(.content),
                banner: .constant(.error("No se pudieron guardar los cambios.")),
                navigation: .title("Banner", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("banner · error")

            // 8 · Banner warning
            ScreenContainer(
                phase: .constant(.content),
                banner: .constant(.warning("Tu sesión expira en 5 minutos.")),
                navigation: .title("Banner", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("banner · warning")

            // 9 · Banner info
            ScreenContainer(
                phase: .constant(.content),
                banner: .constant(.info("Sincronizando datos en segundo plano...")),
                navigation: .title("Banner", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("banner · info")
        }
        .frame(width: 390, height: 700)
    }
}

#endif
