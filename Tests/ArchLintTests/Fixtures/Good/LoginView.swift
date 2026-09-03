import AppFoundation

#if canImport(SwiftUI)
import SwiftUI

public struct LoginView: View {
    @State private var viewModel: LoginViewModel

    public init(viewModel: LoginViewModel) {
        _viewModel = State(initialValue: viewModel)
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
        .navigationTitle("Login")
    }
}
#endif

#if canImport(SwiftUI) && DEBUG
import CoreNetworkingTestSupport

private final class LoginPreviewLogic: LoginLogicProtocol {
    func load() async throws -> [LoginItem] { [] }
}

#Preview {
    // Deliberately references the concrete Logic/Service/Store here — this whole block is
    // #if DEBUG-guarded, exempt from ArchLint.R4 the same way LoginApp's LoginPreview is.
    let mock = MockAPIService()
    let service = LoginService(api: mock)
    let store = LoginStore()
    LoginView(viewModel: LoginViewModel(logic: LoginLogic(loginService: service, loginStore: store)))
}
#endif
