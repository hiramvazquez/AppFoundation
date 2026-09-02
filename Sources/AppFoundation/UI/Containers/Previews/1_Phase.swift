#if canImport(SwiftUI) && DEBUG
import SwiftUI

/// Previews para cada estado de ViewPhase + LoadingStyle.
///
/// Usa `chrome: .custom(...)` para que la barra quede visible en el lienzo de previews sin
/// depender de un `NavigationStack` (`chrome: .native` renderiza sin barra propia — es la
/// barra del sistema la que la aporta — así que estas previews eligen `.custom` a propósito
/// para poder mostrarla). Cada estado es su propio `#Preview` con nombre: el macro no
/// respeta `.previewDisplayName` en subvistas agrupadas.

#Preview("phase · idle") {
    ScreenContainer(
        phase: .constant(.idle),
        chrome: .custom(.title("Idle", style: .solid))
    ) {
        VStack {
            Spacer()
            Text("Sin datos todavía").foregroundStyle(.secondary)
            Spacer()
        }
    }
    .frame(width: 390, height: 700)
}

#Preview("phase · content") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .custom(.title("Content", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("phase · loading · fullScreen") {
    ScreenContainer(
        phase: .constant(.loading(.fullScreen)),
        chrome: .custom(.title("Loading", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("phase · loading · inline") {
    ScreenContainer(
        phase: .constant(.loading(.inline)),
        chrome: .custom(.title("Loading", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("phase · loading · overlay") {
    ScreenContainer(
        phase: .constant(.loading(.overlay)),
        chrome: .custom(.title("Loading", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("phase · empty") {
    ScreenContainer(
        phase: .constant(.empty),
        chrome: .custom(.title("Empty", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("phase · error · con retry") {
    ScreenContainer(
        phase: .constant(
            .error(
                ScreenError(
                    title: "Sin conexión",
                    message: "Comprueba tu conexión e inténtalo de nuevo.",
                    retry: {}
                )
            )
        ),
        chrome: .custom(.title("Error", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("phase · error · sin retry") {
    ScreenContainer(
        phase: .constant(
            .error(
                ScreenError(
                    title: "Sin permiso",
                    message: "No tienes acceso a este contenido."
                )
            )
        ),
        chrome: .custom(.title("Error", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#endif
