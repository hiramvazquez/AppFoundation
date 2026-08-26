#if canImport(SwiftUI)
import SwiftUI

/// Cross-platform color definitions that work on both iOS and macOS.
///
/// These replace direct `UIColor` references (e.g. `Color(.systemBackground)`)
/// which don't compile on macOS. Each property resolves to the appropriate
/// platform color at runtime.
public extension Color {
    /// The primary background color for the platform.
    ///
    /// - iOS: `UIColor.systemBackground` (white in light mode, black in dark mode)
    /// - macOS: `NSColor.windowBackgroundColor`
    static var platformBackground: Color {
        #if canImport(UIKit)
        return Color(.systemBackground)
        #else
        return Color(.windowBackgroundColor)
        #endif
    }

    /// A secondary background color for grouped or elevated content.
    ///
    /// - iOS: `UIColor.secondarySystemBackground`
    /// - macOS: `NSColor.controlBackgroundColor`
    static var platformSecondaryBackground: Color {
        #if canImport(UIKit)
        return Color(.secondarySystemBackground)
        #else
        return Color(.controlBackgroundColor)
        #endif
    }

    /// A subtle fill color for search bars, text fields, and similar controls.
    ///
    /// - iOS: `UIColor.systemGray6`
    /// - macOS: `NSColor.controlBackgroundColor`
    static var platformFill: Color {
        #if canImport(UIKit)
        return Color(.systemGray6)
        #else
        return Color(.controlBackgroundColor)
        #endif
    }
}

#endif
