// Pull-to-refresh: `.refreshable` de SwiftUI espera un closure async — encaja
// directo con la variante estructurada `activity(_:)`. Un fallo se convierte en
// banner (comportamiento por defecto de `activity`/`performActivity`), el
// contenido se queda visible.
import AppFoundation
import SwiftUI

protocol ItemsLoading: Sendable {
    func fetch() async throws -> [String]
}

final class ItemsViewModel: BaseViewModel, ActionHandling {
    private(set) var items: [String] = []
    private let service: any ItemsLoading

    enum Action: Sendable {
        case load
    }

    init(service: any ItemsLoading) {
        self.service = service
    }

    func handle(_ action: Action) {
        switch action {
        case .load: load()
        }
    }

    private func load() {
        performLoad { vm in vm.items = try await vm.service.fetch() }
    }

    func refresh() async {
        await activity { vm in
            vm.items = try await vm.service.fetch()
        }
    }
}

struct ItemsView: View {
    let viewModel: ItemsViewModel

    var body: some View {
        ScreenContainer(viewModel) { send in
            List(viewModel.items, id: \.self) { Text($0) }
                .refreshable { await viewModel.refresh() }
                .onAppear { send(.load) }
        }
    }
}
