#if canImport(SwiftUI)
import SwiftUI

/// Everything an `EmptyViewStyle` needs to render. Empty rendering today never needs data
/// beyond "we're in the empty phase" — this struct exists so a future need (e.g. a
/// suggested action) can be added without an API break.
public struct EmptyConfiguration: Sendable {
    public init() {}
}

/// A pluggable empty-state appearance for `ScreenContainer`/`PhaseView` (AF-15). See
/// `LoadingViewStyle` for the pattern; install with `.emptyViewStyle(_:)`.
public protocol EmptyViewStyle {
    associatedtype Body: View

    @ViewBuilder func makeBody(configuration: EmptyConfiguration) -> Body
}

/// The built-in empty-state appearance — same visuals the previous hardcoded
/// `DefaultEmptyView` provided.
public struct DefaultEmptyViewStyle: EmptyViewStyle {
    public init() {}

    public func makeBody(configuration: EmptyConfiguration) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 34))
            Text("Nothing to show yet", bundle: .module)
                .font(.title3.bold())
            Text("The operation succeeded, but there is no content to display.", bundle: .module)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Type-erased storage (Environment boundary)

/// Boxes any `EmptyViewStyle` so it can live in a single `EnvironmentKey`. See
/// `ErasedView` for why this erasure is necessary and where the package confines it.
struct AnyEmptyViewStyle: EmptyViewStyle {
    private let _makeBody: (EmptyConfiguration) -> ErasedView

    init<S: EmptyViewStyle>(_ style: S) {
        _makeBody = { ErasedView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: EmptyConfiguration) -> ErasedView {
        _makeBody(configuration)
    }
}

private struct EmptyViewStyleKey: EnvironmentKey {
    static let defaultValue = AnyEmptyViewStyle(DefaultEmptyViewStyle())
}

extension EnvironmentValues {
    var emptyViewStyle: AnyEmptyViewStyle {
        get { self[EmptyViewStyleKey.self] }
        set { self[EmptyViewStyleKey.self] = newValue }
    }
}

public extension View {
    /// Installs a custom `EmptyViewStyle` for every `ScreenContainer`/`PhaseView` in this
    /// view's subtree.
    func emptyViewStyle<S: EmptyViewStyle>(_ style: S) -> some View {
        environment(\.emptyViewStyle, AnyEmptyViewStyle(style))
    }
}

#endif
