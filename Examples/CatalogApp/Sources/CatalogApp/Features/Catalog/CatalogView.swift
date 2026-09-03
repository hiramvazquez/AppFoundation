import AppFoundation

#if canImport(SwiftUI)
import SwiftUI

/// The piece an integrator copies first: `ScreenContainer` bound to `CatalogViewModel`,
/// showing cached items immediately and refreshing from the network on appear. Never
/// references `CatalogLogic`/`CatalogService`/`CatalogStore`
/// (`ARQUITECTURA-KIT-2026-09-02.md` §1, rule 4).
public struct CatalogView: View {
    // The composition root builds the view model; the view RETAINS it (`@State`), so the
    // instance that receives `.load` is the one that stays on screen even if SwiftUI
    // re-runs this initializer during a push (PRD-X-05 A3).
    @State private var viewModel: CatalogViewModel

    public init(viewModel: CatalogViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ScreenContainer(viewModel) { send in
            List(viewModel.items) { item in
                Text(item.title)
            }
            .task {
                send(.load)
            }
        }
        .navigationTitle("Catalog")
    }
}
#endif
