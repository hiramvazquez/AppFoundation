#if canImport(SwiftUI)
import SwiftUI

/// Everything a `LoadingViewStyle` needs to render — the `ActivityStyle` that produced it
/// (`.fullScreen`, `.overlay`, or `.inline`), so one style can adapt its presentation to
/// where it is shown.
public struct LoadingConfiguration: Sendable {
    /// Which loading presentation is being rendered.
    public let style: ActivityStyle

    public init(style: ActivityStyle) {
        self.style = style
    }
}

/// A pluggable loading appearance for `ScreenContainer` and `PhaseView` (AF-15).
///
/// This mirrors SwiftUI's own `ButtonStyle`/`ProgressViewStyle` pattern: conform a type,
/// then install it once with `.loadingViewStyle(_:)`. No type erasure at the call site — the
/// package only type-erases internally, at the `Environment` boundary (`ErasedView`).
///
/// ```swift
/// struct BrandLoadingStyle: LoadingViewStyle {
///     func makeBody(configuration: LoadingConfiguration) -> some View {
///         ProgressView().tint(.brand)
///     }
/// }
///
/// ScreenContainer(viewModel) { send in ContentView() }
///     .loadingViewStyle(BrandLoadingStyle())
/// ```
public protocol LoadingViewStyle {
    associatedtype Body: View

    @ViewBuilder func makeBody(configuration: LoadingConfiguration) -> Body
}

/// The built-in loading appearance: a material card for `.fullScreen`/`.overlay`, and a
/// small capsule indicator for `.inline` — same visuals the previous hardcoded
/// `DefaultLoadingView`/`DefaultInlineActivityView` pair provided.
public struct DefaultLoadingViewStyle: LoadingViewStyle {
    public init() {}

    public func makeBody(configuration: LoadingConfiguration) -> some View {
        switch configuration.style {
        case .fullScreen, .overlay:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .padding(32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

        case .inline:
            HStack(spacing: 10) {
                ProgressView()
                Text("Updating…", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 16)
        }
    }
}

// MARK: - Type-erased storage (Environment boundary)

/// Boxes any `LoadingViewStyle` so it can live in a single `EnvironmentKey`. See
/// `ErasedView` for why this erasure is necessary and where the package confines it.
struct AnyLoadingViewStyle: LoadingViewStyle {
    private let _makeBody: (LoadingConfiguration) -> ErasedView

    init<S: LoadingViewStyle>(_ style: S) {
        _makeBody = { ErasedView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: LoadingConfiguration) -> ErasedView {
        _makeBody(configuration)
    }
}

private struct LoadingViewStyleKey: EnvironmentKey {
    static let defaultValue = AnyLoadingViewStyle(DefaultLoadingViewStyle())
}

extension EnvironmentValues {
    var loadingViewStyle: AnyLoadingViewStyle {
        get { self[LoadingViewStyleKey.self] }
        set { self[LoadingViewStyleKey.self] = newValue }
    }
}

public extension View {
    /// Installs a custom `LoadingViewStyle` for every `ScreenContainer`/`PhaseView` in this
    /// view's subtree (`Environment`-propagated, like `ButtonStyle`).
    func loadingViewStyle<S: LoadingViewStyle>(_ style: S) -> some View {
        environment(\.loadingViewStyle, AnyLoadingViewStyle(style))
    }
}

#endif
