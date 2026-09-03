import AppFoundation

#if canImport(SwiftUI)
import SwiftUI

/// The piece an integrator copies first: `ScreenContainer` bound to `CounterViewModel`,
/// sending the three actions this screen recognizes. Never references `CounterLogic`
/// (`ARQUITECTURA-KIT-2026-09-02.md` §1, rule 4) — only `viewModel` (for reads) and `send`
/// (for actions).
public struct CounterView: View {
    // The composition root builds the view model; the view RETAINS it (`@State`), so the
    // same instance survives SwiftUI re-running this initializer (PRD-X-05 A3).
    @State private var viewModel: CounterViewModel

    public init(viewModel: CounterViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ScreenContainer(viewModel) { send in
            VStack(spacing: 20) {
                Text("\(viewModel.count)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()

                HStack(spacing: 16) {
                    Button("−") { send(.decrement) }
                    Button("Reset") { send(.reset) }
                    Button("+") { send(.increment) }
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle("Counter")
    }
}

#Preview {
    NavigationStack {
        CounterView(viewModel: CounterViewModel(logic: CounterLogic()))
    }
}
#endif
