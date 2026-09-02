#if canImport(SwiftUI)
import SwiftUI

/// Everything an `ErrorViewStyle` needs to render — the `ScreenError` that put the screen
/// in `.error`, including its optional retry action.
public struct ErrorConfiguration: Sendable {
    public let error: ScreenError

    public init(error: ScreenError) {
        self.error = error
    }
}

/// A pluggable error appearance for `ScreenContainer`/`PhaseView` (AF-15). See
/// `LoadingViewStyle` for the pattern; install with `.errorViewStyle(_:)`.
public protocol ErrorViewStyle {
    associatedtype Body: View

    @ViewBuilder func makeBody(configuration: ErrorConfiguration) -> Body
}

/// The built-in error appearance — same visuals the previous hardcoded `DefaultErrorView`
/// provided.
public struct DefaultErrorViewStyle: ErrorViewStyle {
    public init() {}

    public func makeBody(configuration: ErrorConfiguration) -> some View {
        let error = configuration.error
        return VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
            Text(error.title)
                .font(.title3.bold())
            Text(error.message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            if let retry = error.retry {
                Button(action: retry) {
                    Text("Retry", bundle: .module)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Type-erased storage (Environment boundary)

/// Boxes any `ErrorViewStyle` so it can live in a single `EnvironmentKey`. See
/// `ErasedView` for why this erasure is necessary and where the package confines it.
struct AnyErrorViewStyle: ErrorViewStyle {
    private let _makeBody: (ErrorConfiguration) -> ErasedView

    init<S: ErrorViewStyle>(_ style: S) {
        _makeBody = { ErasedView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: ErrorConfiguration) -> ErasedView {
        _makeBody(configuration)
    }
}

private struct ErrorViewStyleKey: EnvironmentKey {
    static let defaultValue = AnyErrorViewStyle(DefaultErrorViewStyle())
}

extension EnvironmentValues {
    var errorViewStyle: AnyErrorViewStyle {
        get { self[ErrorViewStyleKey.self] }
        set { self[ErrorViewStyleKey.self] = newValue }
    }
}

public extension View {
    /// Installs a custom `ErrorViewStyle` for every `ScreenContainer`/`PhaseView` in this
    /// view's subtree.
    func errorViewStyle<S: ErrorViewStyle>(_ style: S) -> some View {
        environment(\.errorViewStyle, AnyErrorViewStyle(style))
    }
}

#endif
