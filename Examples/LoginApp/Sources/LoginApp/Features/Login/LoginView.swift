import AppFoundation

#if canImport(SwiftUI)
import SwiftUI

// MARK: - The view

/// The piece an integrator copies first: `ScreenContainer` bound to a `LoginViewModel`,
/// rendering its `.content`/`.loading`/`.error` phases automatically and sending the
/// three actions this screen recognizes. Never references `LoginLogic`/`LoginService`/
/// `APIService` (`ARQUITECTURA-KIT-2026-09-02.md` §1, rule 4) — only `viewModel` (for
/// reads) and `send` (for actions).
public struct LoginView: View {
    let viewModel: LoginViewModel

    public init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScreenContainer(viewModel) { send in
            Form {
                if let session = viewModel.session {
                    Section("Signed in") {
                        Text(session.token)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Credentials") {
                    TextField(
                        "Email",
                        text: Binding(get: { viewModel.email }, set: { send(.updateEmail($0)) })
                    )
                    .textContentType(.emailAddress)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif

                    SecureField(
                        "Password",
                        text: Binding(get: { viewModel.password }, set: { send(.updatePassword($0)) })
                    )
                    .textContentType(.password)
                }

                Button("Log in") {
                    send(.login)
                }
            }
        }
        .navigationTitle("Login")
    }
}

// MARK: - A custom error appearance, installed through `Environment`

/// Proof that pluggable phase appearances never need type erasure at the call site:
/// install one with `.errorViewStyle(_:)`, same as any other `Environment` value.
struct LoginErrorStyle: ErrorViewStyle {
    func makeBody(configuration: ErrorConfiguration) -> some View {
        VStack(spacing: 12) {
            Text(configuration.error.title)
                .font(.headline)
            Text(configuration.error.message)
                .foregroundStyle(.secondary)
            if let retry = configuration.error.retry {
                Button("Try again", action: retry)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}
#endif

// MARK: - Preview: a stub, no real network pipeline

#if canImport(SwiftUI) && DEBUG
import CoreNetworkingTestSupport

/// A `LoginView` wired to `MockAPIService` instead of a live `APIService` — what an
/// integrator's own preview looks like, no test target or network required.
struct LoginPreview: View {
    let viewModel: LoginViewModel

    init(token: String = "preview-token") {
        let mock = MockAPIService()
        mock.stub(LoginRequest.self, returning: LoginRequest.Response(token: token))
        let service = LoginService(api: mock)
        let logic = LoginLogic(loginService: service, sessionStore: SessionStore())
        self.viewModel = LoginViewModel(logic: logic)
    }

    var body: some View {
        NavigationStack {
            LoginView(viewModel: viewModel)
                .errorViewStyle(LoginErrorStyle())
        }
    }
}

#Preview {
    LoginPreview()
}
#endif
