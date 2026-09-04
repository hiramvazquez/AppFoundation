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

@Observable
final class ProfileViewModel: BaseViewModel, ActionHandling {
    // Nonisolated on purpose: without an explicit deinit the compiler synthesizes an isolated
    // one that goes through a back-deploy shim on older OS versions (see AppFoundation's
    // `docs/repros/isolated-deinit-backdeploy.md`). Nothing to clean up here.
    deinit {}

    enum Action: Sendable { case load }
    func handle(_ action: Action) {}
}

struct ProfileScreen: View {
    @State private var viewModel: ProfileViewModel

    init(viewModel: ProfileViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScreenContainer(viewModel) { _ in Text("Perfil") }
            .errorViewStyle(BrandErrorStyle())
    }
}
