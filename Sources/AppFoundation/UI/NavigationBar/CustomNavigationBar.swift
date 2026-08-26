//
//  CustomNavigationBar.swift
//  AppFoundation
//
//  Custom navigation bar component that replaces the native iOS navigation bar.
//  This ensures consistent appearance across iOS versions, including iOS 26+ Liquid Glass.
//

#if canImport(SwiftUI)
import SwiftUI

/// A custom navigation bar that replaces the native iOS NavigationBar.
///
/// This component provides:
/// - Consistent appearance across all iOS versions
/// - Full control over styling (not affected by iOS 26 Liquid Glass)
/// - Proper Safe Area handling for all iPhone models
/// - Badge support for icons
/// - Integrated search bar support
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
    @State private var backButtonHasAppeared = false
    @State private var backButtonIsDisappearing = false

    public init(configuration: NavigationBarConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        if configuration.isVisible {
            VStack(spacing: 0) {
                // Navigation bar content
                if let customContent = configuration.customContent {
                    customContent
                        .frame(maxWidth: .infinity)
                        .frame(height: configuration.style.height)
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
                    .frame(height: configuration.style.height)
                }
                //.padding(.horizontal, 16)

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
                    // Back button with animated appear/disappear
                    Button {
                        // Animate out, then execute action
                        withAnimation(.easeOut(duration: 0.15)) {
                            backButtonIsDisappearing = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            item.action()
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(configuration.style.tintColor)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(NavigationBarButtonStyle())
                    .opacity(backButtonOpacity)
                } else {
                    NavigationBarItemView(
                        item: item,
                        tintColor: configuration.style.tintColor
                    )
                }
            }
        }
        .onAppear {
            guard hasBackButton, !backButtonHasAppeared else { return }
            // Delay to let the push animation complete first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.25)) {
                    backButtonHasAppeared = true
                }
            }
        }
    }

    private var backButtonOpacity: Double {
        if backButtonIsDisappearing {
            return 0
        }
        return backButtonHasAppeared ? 1 : 0
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

        case .text(let text), .largeText(let text):
            Text(text)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(configuration.style.titleColor)
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
    }

    @ViewBuilder
    private var itemContent: some View {
        switch item.content {
        case .systemIcon(let name, let badge):
            iconWithBadge(systemName: name, badge: badge)

        case .icon(let name, let badge):
            customIconWithBadge(name: name, badge: badge)

        case .text(let text):
            Text(text)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(tintColor)

        case .view(let view):
            view
        }
    }

    @ViewBuilder
    private func iconWithBadge(systemName: String, badge: Int?) -> some View {
        let isBack = systemName == "chevron.left"
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemName).renderingMode(.template)
                .font(.system(size: isBack ? 20 : 17, weight: .semibold))
                .foregroundColor(tintColor)
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
                .foregroundColor(tintColor)
                .frame(width: 44, height: 44)

            if let badge = badge, badge > 0 {
                BadgeView(count: badge)
                    .offset(x: 8, y: -4)
            }
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
            .foregroundColor(.white)
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
/// This replaces the native `.searchable()` modifier which is affected by iOS 26 Liquid Glass.
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
                    .foregroundColor(.secondary)
                    .font(.system(size: 15))

                TextField(configuration.placeholder, text: configuration.text)
                    .font(.body)
                    .focused($textFieldFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        configuration.onSubmit?()
                    }
                    .onChange(of: textFieldFocused) { newValue in
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
                            .foregroundColor(.secondary)
                            .font(.system(size: 15))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.platformFill)
            .cornerRadius(10)

            // Cancel button
            if configuration.showsCancelButton && isFocused {
                Button("Cancel") {
                    configuration.text.wrappedValue = ""
                    textFieldFocused = false
                    configuration.onCancel?()
                }
                .font(.body)
                .foregroundColor(tintColor)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - Preview

#if DEBUG
struct CustomNavigationBar_Previews: PreviewProvider {
    static var previews: some View {
        NavigationBarPreviewWrapper()
    }
}

struct NavigationBarPreviewWrapper: View {
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
