//
//  CustomNavigationBar.swift
//  AppFoundation
//
//  Custom navigation bar component — opt-in via `ScreenChrome.custom` (AF-12/AF-13).
//  Prefer the native bar (`ScreenChrome.native` + `navigationTitle`/`toolbar`/`searchable`)
//  for new screens; reach for this only when the native chrome genuinely can't do the job
//  (e.g. a header with an avatar and a greeting, immune to per-OS bar changes).
//

#if canImport(SwiftUI)
import SwiftUI

/// A custom navigation bar — opt-in replacement for the native iOS navigation bar.
///
/// This component provides:
/// - Full control over styling, independent of system chrome changes
/// - Proper Safe Area handling for all iPhone models
/// - Badge support for icons
/// - Integrated search bar support
///
/// Prefer the native bar (`ScreenChrome.native`) unless you need the above. When you do use
/// this, `ScreenContainer(chrome: .custom(...))` installs it together with the workaround
/// that keeps swipe-back working (`PopGestureEnabler`) — using `CustomNavigationBar`
/// directly does not.
///
/// ## Example
/// ```swift
/// CustomNavigationBar(
///     configuration: .withBack(title: "Details") { coordinator.pop() }
/// )
/// ```
///
/// ## Example with Search
/// ```swift
/// CustomNavigationBar(
///     configuration: .withSearch(
///         title: "Games",
///         searchText: $searchText,
///         searchPlaceholder: "Search games..."
///     )
/// )
/// ```
public struct CustomNavigationBar: View {
    private let configuration: NavigationBarConfiguration
    @State private var isSearchFocused = false
    @State private var backButtonVisible = false

    // A11y/Dynamic Type (AF-16): the bar's height scales with the user's text size
    // setting instead of staying pinned at a fixed 44pt. The base value comes from
    // `configuration.style.height`, so `relativeTo: .headline` is supplied — and the
    // wrapper initialized — in `init(configuration:)` below.
    @ScaledMetric private var barHeight: CGFloat

    public init(configuration: NavigationBarConfiguration) {
        self.configuration = configuration
        self._barHeight = ScaledMetric(wrappedValue: configuration.style.height, relativeTo: .headline)
    }

    public var body: some View {
        if configuration.isVisible {
            VStack(spacing: 0) {
                // Navigation bar content
                if let customContent = configuration.customContent {
                    customContent
                        .frame(maxWidth: .infinity)
                        .frame(height: barHeight)
                } else {
                    HStack(spacing: 0) {
                        // Left items
                        leftItemsView
                            .frame(minWidth: 50, alignment: .leading)

                        Spacer()

                        // Title
                        titleView
                            .frame(maxWidth: .infinity)

                        Spacer()

                        // Right items
                        rightItemsView
                            .frame(minWidth: 50, alignment: .trailing)
                    }
                    .frame(height: barHeight)
                }

                // Accessory view or search bar (below title row)
                if let accessoryView = configuration.accessoryView {
                    accessoryView
                        .padding(.bottom, 8)
                } else if let searchBar = configuration.searchBar {
                    NavigationSearchBar(
                        configuration: searchBar,
                        tintColor: configuration.style.tintColor,
                        isFocused: $isSearchFocused
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                // Separator line
                if configuration.style.showSeparator {
                    Divider()
                }
            }
            .contentShape(Rectangle())
            .background(backgroundView)
        }
    }

    // MARK: - Subviews

    private var hasBackButton: Bool {
        configuration.leftItems.contains { $0.isBackButton }
    }

    @ViewBuilder
    private var leftItemsView: some View {
        HStack(spacing: 12) {
            ForEach(configuration.leftItems) { item in
                if item.isBackButton {
                    // Back button: fades in alongside the push transition (C10 — no
                    // guessed GCD delays), and the action fires IMMEDIATELY — the pop
                    // animation is the system's job, not an artificial 0.15s wait.
                    Button(action: item.action) {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(configuration.style.tintColor)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(NavigationBarButtonStyle())
                    .opacity(backButtonVisible ? 1 : 0)
                    // AF-13/AF-16: VoiceOver read "chevron left" before this — a
                    // localized label and the button trait make it announce as a
                    // real, actionable "Back" button.
                    .accessibilityLabel(L10n.back)
                    .accessibilityAddTraits(.isButton)
                } else {
                    NavigationBarItemView(
                        item: item,
                        tintColor: configuration.style.tintColor
                    )
                }
            }
        }
        .onAppear {
            guard hasBackButton, !backButtonVisible else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                backButtonVisible = true
            }
        }
    }

    @ViewBuilder
    private var rightItemsView: some View {
        HStack(spacing: 12) {
            ForEach(configuration.rightItems) { item in
                NavigationBarItemView(item: item, tintColor: configuration.style.tintColor)
            }
        }
    }

    @ViewBuilder
    private var titleView: some View {
        switch configuration.title {
        case .none:
            EmptyView()

        case .text(let text):
            Text(text)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(configuration.style.titleColor)
                .lineLimit(1)

        case .custom(let view):
            view
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch configuration.style.background {
        case .solid(let color):
            color

        case .blur(let material):
            Rectangle()
                .fill(material)

        case .gradient(let gradient):
            gradient
        }
    }
}

// MARK: - Navigation Bar Item View

/// Renders a single navigation bar item (button).
struct NavigationBarItemView: View {
    let item: NavigationBarItem
    let tintColor: Color

    init(item: NavigationBarItem, tintColor: Color) {
        self.item = item
        self.tintColor = tintColor
    }

    var body: some View {
        Button(action: item.action) {
            itemContent
        }
        .buttonStyle(NavigationBarButtonStyle())
        .accessibilityAddTraits(.isButton)
        .modifier(CloseButtonAccessibility(isClose: item.role == .close))
    }

    @ViewBuilder
    private var itemContent: some View {
        switch item.content {
        case .systemIcon(let name, let badge):
            iconWithBadge(systemName: name, badge: badge, emphasized: item.role == .back)

        case .icon(let name, let badge):
            customIconWithBadge(name: name, badge: badge)

        case .text(let text):
            Text(text)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(tintColor)

        case .view(let view):
            view
        }
    }

    @ViewBuilder
    private func iconWithBadge(systemName: String, badge: Int?, emphasized: Bool) -> some View {
        // A11: emphasis keys off the item's ROLE, not off the icon being "chevron.left".
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemName).renderingMode(.template)
                .font(emphasized ? .headline.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(tintColor)
                .frame(width: 44, height: 44)

            if let badge = badge, badge > 0 {
                BadgeView(count: badge)
                    .offset(x: 8, y: -4)
            }
        }
    }

    @ViewBuilder
    private func customIconWithBadge(name: String, badge: Int?) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(name).renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundStyle(tintColor)
                .frame(width: 44, height: 44)

            if let badge = badge, badge > 0 {
                BadgeView(count: badge)
                    .offset(x: 8, y: -4)
            }
        }
    }
}

/// Adds the localized "Close" accessibility label to close-role items (AF-13/AF-16); a
/// no-op `ViewModifier` for every other role so `NavigationBarItemView` doesn't need a
/// type-erased branch to apply it conditionally.
private struct CloseButtonAccessibility: ViewModifier {
    let isClose: Bool

    func body(content: Content) -> some View {
        if isClose {
            content.accessibilityLabel(L10n.close)
        } else {
            content
        }
    }
}

// MARK: - Badge View

/// A small badge indicator for notification counts.
struct BadgeView: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.red)
            .clipShape(Capsule())
    }
}

// MARK: - Button Style

/// Custom button style for navigation bar items.
struct NavigationBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Navigation Search Bar

/// A custom search bar component for the navigation bar.
///
/// This replaces the native `.searchable()` modifier — only relevant together with
/// `CustomNavigationBar`; screens using the native bar should prefer `.searchable()`
/// directly, which already handles keyboard, tokens, suggestions and scopes for free.
struct NavigationSearchBar: View {
    let configuration: SearchBarConfiguration
    let tintColor: Color
    @Binding var isFocused: Bool
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .accessibilityHidden(true)

                TextField(configuration.placeholder, text: configuration.text)
                    .font(.body)
                    .focused($textFieldFocused)
                    .submitLabel(.search)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityLabel(Text(configuration.placeholder))
                    .onSubmit {
                        configuration.onSubmit?()
                    }
                    .onChange(of: textFieldFocused) { _, newValue in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isFocused = newValue
                        }
                    }

                // Clear button
                if !configuration.text.wrappedValue.isEmpty {
                    Button {
                        configuration.text.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .accessibilityLabel(L10n.close)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.platformFill)
            .clipShape(.rect(cornerRadius: 10))

            // Cancel button
            if configuration.showsCancelButton && isFocused {
                Button {
                    configuration.text.wrappedValue = ""
                    textFieldFocused = false
                    configuration.onCancel?()
                } label: {
                    Text("Cancel", bundle: .module)
                }
                .font(.body)
                .foregroundStyle(tintColor)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationBarPreviewWrapper()
}

private struct NavigationBarPreviewWrapper: View {
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 20) {
            // Default with title
            CustomNavigationBar(
                configuration: .title("Home")
            )

            // With back button
            CustomNavigationBar(
                configuration: .withBack(title: "Details", style: .solid) { }
            )

            // With search bar
            CustomNavigationBar(
                configuration: .withSearch(
                    title: "Games",
                    searchText: $searchText,
                    searchPlaceholder: "Search games..."
                )
            )

            // With multiple items
            CustomNavigationBar(
                configuration: NavigationBarConfiguration(
                    title: .text("Messages"),
                    leftItems: [.back { }],
                    rightItems: [
                        .icon("bell", badge: 5) { },
                        .icon("gear") { }
                    ],
                    style: .solid
                )
            )

            // Full featured: back + search + right items
            CustomNavigationBar(
                configuration: NavigationBarConfiguration(
                    title: .text("Catalog"),
                    leftItems: [.back { }],
                    rightItems: [.icon("slider.horizontal.3") { }],
                    searchBar: SearchBarConfiguration(
                        text: $searchText,
                        placeholder: "Search..."
                    ),
                    style: .solid
                )
            )

            Spacer()
        }
        .background(Color.gray.opacity(0.2))
    }
}
#endif

#endif
