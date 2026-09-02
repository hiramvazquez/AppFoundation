#if canImport(SwiftUI) && DEBUG
import SwiftUI

/// Previews para ActivityState, AlertState y BannerState. Cada caso es su propio
/// `#Preview` con nombre: el macro no respeta `.previewDisplayName` en subvistas agrupadas.

#Preview("activity · inline") {
    ScreenContainer(
        phase: .constant(.content),
        activity: .constant(.loading(.inline)),
        chrome: .custom(.title("Activity", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("activity · overlay") {
    ScreenContainer(
        phase: .constant(.content),
        activity: .constant(.loading(.overlay)),
        chrome: .custom(.title("Activity", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("alert · info") {
    ScreenContainer(
        phase: .constant(.content),
        alert: .constant(.info(
            title: "Actualización disponible",
            message: "Hay una nueva versión. Actualiza para continuar."
        )),
        chrome: .custom(.title("Alert", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("alert · confirmation") {
    ScreenContainer(
        phase: .constant(.content),
        alert: .constant(.confirmation(
            title: "¿Enviar reporte?",
            message: "Se enviará al equipo de moderación.",
            confirm: "Enviar",
            cancel: "Cancelar",
            onConfirm: {}
        )),
        chrome: .custom(.title("Alert", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("alert · destructive") {
    ScreenContainer(
        phase: .constant(.content),
        alert: .constant(.destructive(
            title: "¿Eliminar cuenta?",
            message: "Esta acción es irreversible. Se eliminará toda tu información.",
            confirm: "Eliminar",
            cancel: "Cancelar",
            onConfirm: {}
        )),
        chrome: .custom(.title("Alert", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("banner · success") {
    ScreenContainer(
        phase: .constant(.content),
        banner: .constant(.success("Perfil actualizado correctamente.")),
        chrome: .custom(.title("Banner", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("banner · error") {
    ScreenContainer(
        phase: .constant(.content),
        banner: .constant(.error("No se pudieron guardar los cambios.")),
        chrome: .custom(.title("Banner", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("banner · warning") {
    ScreenContainer(
        phase: .constant(.content),
        banner: .constant(.warning("Tu sesión expira en 5 minutos.")),
        chrome: .custom(.title("Banner", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("banner · info") {
    ScreenContainer(
        phase: .constant(.content),
        banner: .constant(.info("Sincronizando datos en segundo plano...")),
        chrome: .custom(.title("Banner", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#endif
