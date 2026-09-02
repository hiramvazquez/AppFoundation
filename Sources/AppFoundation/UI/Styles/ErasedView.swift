#if canImport(SwiftUI)
import SwiftUI

/// The ONE place in this package where `AnyView` is used (AF-15/AF-16).
///
/// SwiftUI's type system has no way to store a *heterogeneous* `View`-conforming value in
/// a homogeneous property or collection element: an item in a `[NavigationBarItem]` array,
/// a custom navigation title, an accessory view, or a `LoadingViewStyle`/`ErrorViewStyle`/
/// `EmptyViewStyle`/`BannerViewStyle` propagated through `Environment`. `some View` fixes a
/// single concrete type for the whole declaration, not per call site — none of those cases
/// have one, since the concrete view type differs at every call site and is only known
/// where the value is first produced.
///
/// This box is that boundary: confined to a single file, never exposed as `AnyView` in the
/// public API (call sites see `ErasedView`, a plain `View`), and used only where storage —
/// not composition — requires it. Every other place in this package uses `some View` /
/// generics instead.
///
/// Public because it appears in public enum cases and properties (`NavigationBarItem`,
/// `NavigationBarConfiguration`) — Swift requires the associated/stored type to be at
/// least as visible as the declaration that holds it. It is still a plain `View`: nothing
/// about `AnyView` leaks into any public signature.
///
/// ## The four remaining uses (DC-AF-5)
///
/// All four live in `NavigationBarItem.swift`, and all four are storage for the *custom*
/// navigation bar — an opt-in surface (`ScreenChrome.custom`, AF-12/AF-13). With `.native`
/// the default, most screens never touch any of these:
///
/// - `NavigationBarItem.NavigationBarItemContent.view`: a caller-supplied bar item view —
///   items of different concrete `View` types share one `[NavigationBarItem]` array.
/// - `NavigationBarTitle.custom`: a caller-supplied title view (logo, inline search field, …).
/// - `NavigationBarConfiguration.accessoryView`: an optional view below the bar (same slot
///   as `searchBar`, which needs no erasure because it isn't a `View` — see
///   `SearchBarConfiguration`).
/// - `NavigationBarConfiguration.customContent`: a full-width view replacing the entire
///   left/title/right layout.
///
/// Each stores a heterogeneous, caller-determined `View` in a property/enum case whose
/// declared type must be fixed — the same structural reason documented above. Since
/// `.custom` is opt-in, this erasure never reaches a screen that sticks with `.native`.
public struct ErasedView: View {
    private let box: AnyView

    init<V: View>(_ view: V) {
        self.box = AnyView(view)
    }

    public var body: some View { box }
}

#endif
