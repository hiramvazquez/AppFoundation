import AppFoundation

#if canImport(SwiftUI)
import SwiftUI

/// The piece an integrator copies first: `ScreenContainer` bound to `CatalogViewModel`,
/// showing cached items immediately and refreshing from the network on appear. Never
/// references `CatalogLogic`/`CatalogService`/`CatalogStore`
/// (`ARQUITECTURA-KIT-2026-09-02.md` §1, rule 4).
public struct CatalogView: View {
    let viewModel: CatalogViewModel

    public init(viewModel: CatalogViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScreenContainer(viewModel) { send in
            List(viewModel.items) { item in
                Text(item.title)
            }
            .onAppear {
                send(.load)
            }
        }
        .navigationTitle("Catalog")
    }
}
#endif
