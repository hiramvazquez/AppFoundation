// Un DomainError por feature (nunca APIError/SwiftData fuera de la Logic) más un
// ErrorPresenting a nivel de app que sabe presentarlo sin que la app dependa de red.
import AppFoundation

enum LoginError: DomainError {
    case invalidCredentials
    case offline

    var isRetryable: Bool {
        switch self {
        case .offline: true
        case .invalidCredentials: false
        }
    }

    var screenError: ScreenError {
        switch self {
        case .invalidCredentials:
            return ScreenError(title: "Credenciales inválidas", message: "Revisa tu email y contraseña.")
        case .offline:
            return ScreenError(title: "Sin conexión", message: "Revisa tu red e inténtalo de nuevo.")
        }
    }
}

struct AppErrorPresenter: ErrorPresenting {
    func screenError(for error: any Error, fallbackTitle: String, retry: Action?) -> ScreenError {
        if let domain = error as? any DomainError {
            return domain.screenError
        }
        return DefaultErrorPresenter().screenError(for: error, fallbackTitle: fallbackTitle, retry: retry)
    }
}

// Al arrancar la app:
BaseViewModel.errorPresenter = AppErrorPresenter()
