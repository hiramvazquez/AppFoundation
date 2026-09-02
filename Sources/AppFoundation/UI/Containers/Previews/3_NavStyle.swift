#if canImport(SwiftUI) && DEBUG
import SwiftUI

/// Previews para cada estilo visual de `NavigationBarStyle` y `NavigationPlacement`
/// (`chrome: .custom(...)` — estilos de barra solo tienen sentido para la barra opt-in).
/// Cada caso es su propio `#Preview` con nombre: el macro no respeta `.previewDisplayName`
/// en subvistas agrupadas.

#Preview("style · default") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .custom(.title("Default", style: .default))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("style · solid") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .custom(.title("Solid", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("style · blur") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .custom(.title("Blur", style: .blur))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("style · transparent") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .custom(
            NavigationBarConfiguration(
                title: .text("Transparent"),
                leftItems: [.back(action: {})],
                style: .transparent
            )
        ),
        backgroundColor: .clear
    ) {
        ZStack {
            LinearGradient(colors: [.purple, .blue, .cyan], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack {
                Spacer()
                Text("Contenido full-bleed").foregroundStyle(Color.white).font(.title3.weight(.semibold))
                Spacer()
            }
        }
    }
    .frame(width: 390, height: 700)
}

#Preview("style · solid custom") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .custom(
            NavigationBarConfiguration(
                title: .text("Custom Color"),
                leftItems: [.back(action: {})],
                rightItems: [.icon("ellipsis", action: {})],
                style: NavigationBarStyle(background: .solid(.indigo), titleColor: .white, tintColor: .white)
            )
        )
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("style · gradient") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .custom(
            NavigationBarConfiguration(
                title: .text("Gradient"),
                leftItems: [.back(action: {})],
                style: NavigationBarStyle(
                    background: .gradient(
                        LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing)
                    ),
                    titleColor: .white,
                    tintColor: .white
                )
            )
        )
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("placement · stack") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .custom(.withBack(title: "Stack", style: .solid) {}, placement: .stack)
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("placement · overlay") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .custom(.withBack(title: "Overlay", style: .blur) {}, placement: .overlay)
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#endif
