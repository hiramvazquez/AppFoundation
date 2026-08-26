#if canImport(SwiftUI) && DEBUG
import SwiftUI

/// Previews para cada configuración de NavigationBarConfiguration.
struct ScreenContainer_NavBar_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 1 · Hidden
            ScreenContainer(
                phase: .constant(.content),
                navigation: .hidden
            ) {
                VStack {
                    Spacer()
                    Text("Sin barra de navegación").font(.headline)
                    Spacer()
                }
            }
            .previewDisplayName("hidden")

            // 2 · Title
            ScreenContainer(
                phase: .constant(.content),
                navigation: .title("Home", style: .solid)
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("title")

            // 3 · withBack
            ScreenContainer(
                phase: .constant(.content),
                navigation: .withBack(title: "Detalle", style: .solid) {}
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("withBack")

            // 4 · withClose
            ScreenContainer(
                phase: .constant(.content),
                navigation: .withClose(title: "Nuevo post", style: .solid) {}
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("withClose")

            // 5 · Right items con badge
            ScreenContainer(
                phase: .constant(.content),
                navigation: NavigationBarConfiguration(
                    title: .text("Mensajes"),
                    leftItems: [.back(action: {})],
                    rightItems: [
                        .icon("bell", badge: 3, action: {}),
                        .icon("square.and.pencil", action: {})
                    ],
                    style: .solid
                )
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("rightItems + badge")
        }
        .frame(width: 390, height: 700)

        Group {
            // 6 · withSearch
            ScreenContainer(
                phase: .constant(.content),
                navigation: .withSearch(
                    title: "Explorar",
                    searchText: .constant(""),
                    searchPlaceholder: "Buscar...",
                    style: .solid
                )
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("withSearch")

            // 7 · withBackAndSearch
            ScreenContainer(
                phase: .constant(.content),
                navigation: .withBackAndSearch(
                    title: "Catálogo",
                    searchText: .constant("Swift"),
                    style: .solid,
                    backAction: {}
                )
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("withBackAndSearch")

            // 8 · withBackAndAccessory (filter chips)
            ScreenContainer(
                phase: .constant(.content),
                navigation: .withBackAndAccessory(
                    title: "Jugadores",
                    style: .solid,
                    backAction: {}
                ) {
                    HStack(spacing: 8) {
                        ForEach(["Todos", "Activos", "Inactivos"], id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(tag == "Todos" ? Color.accentColor : Color.secondary.opacity(0.15))
                                .foregroundColor(tag == "Todos" ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("withBackAndAccessory")

            // 9 · Custom (avatar + saludo)
            ScreenContainer(
                phase: .constant(.content),
                navigation: .custom(style: .solid) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.2))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text("JD").font(.caption.weight(.bold)).foregroundColor(.accentColor)
                            )
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Buenos días,").font(.caption).foregroundColor(.secondary)
                            Text("John Doe").font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                        Button {} label: {
                            Image(systemName: "bell.badge").font(.title3)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                }
            ) {
                PreviewSampleList()
            }
            .previewDisplayName("custom content")
        }
        .frame(width: 390, height: 700)
    }
}

#endif
