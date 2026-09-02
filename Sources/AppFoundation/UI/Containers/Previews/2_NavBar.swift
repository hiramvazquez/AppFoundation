#if canImport(SwiftUI) && DEBUG
import SwiftUI

/// Previews para `ScreenChrome` — `.native` primero (el default recomendado), luego cada
/// configuración de `.custom(NavigationBarConfiguration)` como opt-in. Cada caso es su
/// propio `#Preview` con nombre: el macro no respeta `.previewDisplayName` en subvistas
/// agrupadas.

#Preview("chrome · native") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .native
    ) {
        VStack {
            Spacer()
            Text("chrome: .native — usa navigationTitle/toolbar del contenedor real")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
    }
    .frame(width: 390, height: 700)
}

#Preview("chrome · custom · title") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .custom(.title("Home", style: .solid))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("chrome · custom · withBack") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .custom(.withBack(title: "Detalle", style: .solid) {})
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("chrome · custom · withClose") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .custom(.withClose(title: "Nuevo post", style: .solid) {})
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("chrome · custom · rightItems + badge") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .custom(NavigationBarConfiguration(
            title: .text("Mensajes"),
            leftItems: [.back(action: {})],
            rightItems: [
                .icon("bell", badge: 3, action: {}),
                .icon("square.and.pencil", action: {})
            ],
            style: .solid
        ))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("chrome · custom · withSearch") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .custom(.withSearch(
            title: "Explorar",
            searchText: .constant(""),
            searchPlaceholder: "Buscar...",
            style: .solid
        ))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("chrome · custom · withBackAndSearch") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .custom(.withBackAndSearch(
            title: "Catálogo",
            searchText: .constant("Swift"),
            style: .solid,
            backAction: {}
        ))
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("chrome · custom · withBackAndAccessory") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .custom(.withBackAndAccessory(
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
                        .foregroundStyle(tag == "Todos" ? .white : .primary)
                        .clipShape(Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        })
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#Preview("chrome · custom · custom content") {
    ScreenContainer(
        phase: .constant(.content),
        chrome: .custom(.custom(style: .solid) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text("JD").font(.caption.weight(.bold)).foregroundStyle(Color.accentColor)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Buenos días,").font(.caption).foregroundStyle(.secondary)
                    Text("John Doe").font(.subheadline.weight(.semibold))
                }
                Spacer()
                Button {} label: {
                    Image(systemName: "bell.badge").font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
        })
    ) {
        PreviewSampleList()
    }
    .frame(width: 390, height: 700)
}

#endif
