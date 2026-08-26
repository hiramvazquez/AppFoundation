#if canImport(SwiftUI) && DEBUG
import SwiftUI

/// Previews para cada estilo visual de NavigationBarStyle y NavigationPlacement.
struct ScreenContainer_NavStyle_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 1 · Default (fondo transparente)
            ScreenContainer(
                phase: .constant(.content),
                navigation: .title("Default", style: .default)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("style · default")

            // 2 · Solid
            ScreenContainer(
                phase: .constant(.content),
                navigation: .title("Solid", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("style · solid")

            // 3 · Blur
            ScreenContainer(
                phase: .constant(.content),
                navigation: .title("Blur", style: .blur)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("style · blur")

            // 4 · Transparent (barra blanca sobre gradiente)
            ScreenContainer(
                phase: .constant(.content),
                navigation: NavigationBarConfiguration(
                    title: .text("Transparent"),
                    leftItems: [.back(action: {})],
                    style: .transparent
                ),
                backgroundColor: .clear
            ) {
                ZStack {
                    LinearGradient(colors: [.purple, .blue, .cyan], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                    VStack { Spacer(); Text("Contenido full-bleed").foregroundColor(.white).font(.title3.weight(.semibold)); Spacer() }
                }
            }
            .previewDisplayName("style · transparent")

            // 5 · Color personalizado
            ScreenContainer(
                phase: .constant(.content),
                navigation: NavigationBarConfiguration(
                    title: .text("Custom Color"),
                    leftItems: [.back(action: {})],
                    rightItems: [.icon("ellipsis", action: {})],
                    style: NavigationBarStyle(background: .solid(.indigo), titleColor: .white, tintColor: .white)
                )
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("style · solid custom")
        }
        .frame(width: 390, height: 700)

        Group {
            // 6 · Gradient
            ScreenContainer(
                phase: .constant(.content),
                navigation: NavigationBarConfiguration(
                    title: .text("Gradient"),
                    leftItems: [.back(action: {})],
                    style: NavigationBarStyle(
                        background: .gradient(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing)),
                        titleColor: .white,
                        tintColor: .white
                    )
                )
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("style · gradient")

            // 7 · Placement: stack (por defecto)
            ScreenContainer(
                phase: .constant(.content),
                navigation: .withBack(title: "Stack", style: .solid) {},
                navigationPlacement: .stack
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("placement · stack")

            // 8 · Placement: overlay (flota sobre el scroll)
            ScreenContainer(
                phase: .constant(.content),
                navigation: .withBack(title: "Overlay", style: .blur) {},
                navigationPlacement: .overlay
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("placement · overlay")
        }
        .frame(width: 390, height: 700)
    }
}

#endif
