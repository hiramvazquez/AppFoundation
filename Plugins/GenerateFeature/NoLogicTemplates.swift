import Foundation

/// `--no-logic`: an escape hatch for a screen that genuinely has no business rule of its
/// own — the `ViewModel` inherits `BaseViewModel` directly instead of
/// `LogicViewModel<any XxxLogicProtocol>`, and no `Logic`/`Service`/`Store` files are
/// generated at all.
///
/// This path is built directly here rather than through `AppFoundation/Templates/*.txt`:
/// it is a deliberately minimal, rarely-used variant (every other combination goes through
/// the four real `ARQUITECTURA-KIT-2026-09-02.md` §1 variants and their templates), and
/// keeping it out of the mustache-flag matrix in `Logic.swift.txt`/`Module.swift.txt` kept
/// those templates readable.
extension GenerateFeaturePlugin {
    static func noLogicView(feature: String) -> String {
        """
        import AppFoundation

        #if canImport(SwiftUI)
        import SwiftUI

        /// Generado por `swift package generate-feature \(feature) --no-logic`. Sin Logic:
        /// esta pantalla no tiene regla de negocio propia — si alguna vez la necesita,
        /// vuelve a generar sin `--no-logic` (o crea `\(feature)Logic.swift` a mano).
        public struct \(feature)View: View {
            let viewModel: \(feature)ViewModel

            public init(viewModel: \(feature)ViewModel) {
                self.viewModel = viewModel
            }

            public var body: some View {
                ScreenContainer(viewModel) { send in
                    Text("Hola mundo")
                        .onAppear {
                            send(.load)
                        }
                }
                .navigationTitle("\(feature)")
            }
        }

        #Preview {
            NavigationStack {
                \(feature)View(viewModel: \(feature)ViewModel())
            }
        }
        #endif

        """
    }

    static func noLogicViewModel(feature: String) -> String {
        """
        import AppFoundation
        import Foundation

        /// Generado por `swift package generate-feature \(feature) --no-logic`. Hereda de
        /// `BaseViewModel` directamente — sin `Logic` inyectada. Sin `init` propio: los tres
        /// parámetros de `BaseViewModel.init` son opcionales, así que Swift lo hereda tal
        /// cual (una subclase sin designated initializers propios hereda los del padre) y
        /// `\(feature)ViewModel()` ya compila.
        @MainActor
        public final class \(feature)ViewModel: BaseViewModel, ActionHandling {
            /// Cada acción que reconoce esta pantalla.
            public enum Action: Sendable {
                case load
            }

            public func handle(_ action: Action) {
                switch action {
                case .load: setContent()
                }
            }
        }

        """
    }

    static func noLogicModule(feature: String) -> String {
        """
        import AppFoundation

        /// Registra el feature \(feature) en un `Container` — sin Logic (M4).
        public struct \(feature)Module: DependencyModule {
            public init() {}

            public func register(in container: Container) {
                container.register(\(feature)ViewModel.self, lifecycle: .transient) { _ in
                    \(feature)ViewModel()
                }
            }
        }

        """
    }

    static func noLogicViewModelTests(feature: String, module: String) -> String {
        """
        import Foundation
        import Testing

        @testable import \(module)

        @Suite("\(feature)ViewModel")
        @MainActor
        struct \(feature)ViewModelTests {
            @Test("handle(.load) reaches .content")
            func loadReachesContent() {
                let viewModel = \(feature)ViewModel()

                viewModel.handle(.load)

                #expect(viewModel.phase == .content)
            }
        }

        """
    }
}
