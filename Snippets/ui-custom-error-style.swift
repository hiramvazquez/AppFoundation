// Un ErrorViewStyle propio, propagado por Environment — sin AnyView en el call site,
// el mismo patrón que ButtonStyle/ProgressViewStyle de SwiftUI.
import AppFoundation
import SwiftUI

struct BrandErrorStyle: ErrorViewStyle {
    func makeBody(configuration: ErrorConfiguration) -> some View {
        VStack(spacing: 12) {
            Text(configuration.error.title).font(.headline)
            Text(configuration.error.message)
            if let retry = configuration.error.retry {
                Button("Reintentar", action: retry)
            }
        }
        .padding()
    }
}

final class ProfileViewModel: BaseViewModel, ActionHandling {
    enum Action: Sendable { case load }
    func handle(_ action: Action) {}
}

struct ProfileScreen: View {
    let viewModel: ProfileViewModel

    var body: some View {
        ScreenContainer(viewModel) { _ in Text("Perfil") }
            .errorViewStyle(BrandErrorStyle())
    }
}
