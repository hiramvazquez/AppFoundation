//
//  DeepLink.swift
//  AppFoundation
//
//  Generic deep link system for handling URL-based navigation.
//

import Foundation

/// Protocol for defining deep link types in your app.
///
/// Implement this protocol to define the deep link cases your app supports.
///
/// ## Example
/// ```swift
/// enum AppDeepLink: DeepLinkType {
///     case notifications
///     case profile(userId: String)
///     case game(gameId: String)
/// }
/// ```
public protocol DeepLinkType {
    /// Parse a URL into a deep link case
    static func parse(_ url: URL) -> Self?
}
