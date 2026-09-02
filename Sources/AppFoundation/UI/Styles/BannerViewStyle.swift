#if canImport(SwiftUI)
import SwiftUI

/// Everything a `BannerViewStyle` needs to render — the `BannerState` to show, and the
/// action that dismisses it (tap-to-dismiss, a close button, or the auto-dismiss timer's
/// removal all resolve to calling this).
public struct BannerConfiguration {
    public let banner: BannerState
    public let dismiss: () -> Void

    public init(banner: BannerState, dismiss: @escaping () -> Void) {
        self.banner = banner
        self.dismiss = dismiss
    }
}

/// A pluggable banner appearance for `ScreenContainer` (AF-15). See `LoadingViewStyle` for
/// the pattern; install with `.bannerViewStyle(_:)`.
public protocol BannerViewStyle {
    associatedtype Body: View

    @ViewBuilder func makeBody(configuration: BannerConfiguration) -> Body
}

/// The built-in banner appearance — same visuals the previous hardcoded `DefaultBannerView`
/// provided.
public struct DefaultBannerViewStyle: BannerViewStyle {
    public init() {}

    public func makeBody(configuration: BannerConfiguration) -> some View {
        Text(configuration.banner.message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(backgroundColor(for: configuration.banner.style))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .onTapGesture(perform: configuration.dismiss)
    }

    private func backgroundColor(for style: BannerState.Style) -> Color {
        switch style {
        case .success: return .green
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Type-erased storage (Environment boundary)

/// Boxes any `BannerViewStyle` so it can live in a single `EnvironmentKey`. See
/// `ErasedView` for why this erasure is necessary and where the package confines it.
struct AnyBannerViewStyle: BannerViewStyle {
    private let _makeBody: (BannerConfiguration) -> ErasedView

    init<S: BannerViewStyle>(_ style: S) {
        _makeBody = { ErasedView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: BannerConfiguration) -> ErasedView {
        _makeBody(configuration)
    }
}

private struct BannerViewStyleKey: EnvironmentKey {
    static let defaultValue = AnyBannerViewStyle(DefaultBannerViewStyle())
}

extension EnvironmentValues {
    var bannerViewStyle: AnyBannerViewStyle {
        get { self[BannerViewStyleKey.self] }
        set { self[BannerViewStyleKey.self] = newValue }
    }
}

public extension View {
    /// Installs a custom `BannerViewStyle` for every `ScreenContainer` in this view's
    /// subtree.
    func bannerViewStyle<S: BannerViewStyle>(_ style: S) -> some View {
        environment(\.bannerViewStyle, AnyBannerViewStyle(style))
    }
}

#endif
