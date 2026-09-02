// Un formulario: validación local antes de llamar a la Logic, submit vía
// `performActivity` (el contenido — el propio formulario — se queda visible).
import AppFoundation

enum SignupError: DomainError {
    case invalidEmail

    var screenError: ScreenError {
        ScreenError(title: "Email inválido", message: "Revisa el formato del correo.")
    }
}

// `Sendable` explícito: sin `NonisolatedNonsendingByDefault` habilitado (como en este
// propio paquete, ver `AppFoundation/Package.swift`) un Logic nonisolated + async cruza
// de actor al llamarlo desde un ViewModel `@MainActor`.
protocol SignupLogicProtocol: Logic, Sendable {
    func signUp(email: String, password: String) async throws(SignupError)
}

final class SignupViewModel: LogicViewModel<any SignupLogicProtocol>, ActionHandling {
    var email = ""
    var password = ""

    enum Action: Sendable {
        case submit
    }

    func handle(_ action: Action) {
        switch action {
        case .submit: submit()
        }
    }

    private func submit() {
        guard email.contains("@") else {
            handleActivityError(SignupError.invalidEmail, strategy: .banner)
            return
        }
        performActivity { vm in
            try await vm.logic.signUp(email: vm.email, password: vm.password)
        }
    }
}
