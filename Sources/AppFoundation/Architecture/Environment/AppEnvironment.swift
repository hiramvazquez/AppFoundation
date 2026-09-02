import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Provides information about the current runtime environment.
///
/// A namespace (`enum` with no cases — there is no state to instantiate): build
/// type, distribution channel, app metadata, device and system facts.
///
/// What it deliberately does NOT offer (audit AF-20): a "running under tests or
/// previews" flag. Detecting the test runner by class name or the previews
/// environment variable is a heuristic that production code should never branch
/// on; inject the behaviour you want in tests instead of asking the environment.
///
/// ## Example - Conditional Logging
/// ```swift
/// if AppEnvironment.isDebug {
///     print("Debug info: \(data)")
/// }
/// ```
///
/// ## Example - Environment-Based Configuration
/// ```swift
/// let apiURL = AppEnvironment.isProduction
///     ? "https://api.myapp.com"
///     : "https://staging-api.myapp.com"
/// ```
public nonisolated enum AppEnvironment {

    // MARK: - Environment Detection

    /// Detects if running under TestFlight.
    ///
    /// Useful for enabling beta features or analytics.
    ///
    /// - Note: Implemented via the sandbox receipt check. `Bundle.appStoreReceiptURL`
    ///   is deprecated as of iOS 18 (StoreKit 2's `AppTransaction` replaces receipts),
    ///   but the replacement is async-only and this API is deliberately synchronous.
    ///   The private accessor below carries the availability annotation so the decision
    ///   stays visible; revisit when the package adopts StoreKit 2.
    public static var isTestFlight: Bool {
        legacySandboxReceiptCheck
    }

    @available(iOS, introduced: 17.0, deprecated: 18.0, message: "Bundle.appStoreReceiptURL is deprecated; migrate to StoreKit 2 AppTransaction when isTestFlight can become async")
    @available(macOS, introduced: 14.0, deprecated: 15.0, message: "Bundle.appStoreReceiptURL is deprecated; migrate to StoreKit 2 AppTransaction when isTestFlight can become async")
    private static var legacySandboxReceiptCheck: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// Detects if this is a debug build.
    public static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Detects if this is a release/production build.
    public static var isRelease: Bool {
        !isDebug
    }

    /// Detects if running in production (release build, not TestFlight).
    ///
    /// Use this to enable production-only features like crash reporting.
    public static var isProduction: Bool {
        isRelease && !isTestFlight
    }

    /// Detects if running in the iOS Simulator.
    public static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Detects if running on a physical device.
    public static var isDevice: Bool {
        !isSimulator
    }

    // MARK: - App Metadata

    /// The app's display name from Info.plist.
    ///
    /// Falls back to bundle name if display name is not set.
    public static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Unknown"
    }

    /// The app's version string (e.g., "1.2.3").
    ///
    /// This is the marketing version shown to users.
    public static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// The app's build number (e.g., "42").
    ///
    /// This is the internal build identifier.
    public static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// Full version string including build number (e.g., "1.2.3 (42)").
    public static var fullVersion: String {
        "\(appVersion) (\(buildNumber))"
    }

    /// The app's bundle identifier (e.g., "com.company.app").
    public static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    // MARK: - Device Information

    #if canImport(UIKit)
    /// The device model name (e.g., "iPhone", "iPad").
    @MainActor
    public static var deviceModel: String {
        UIDevice.current.model
    }

    /// The device's user-assigned name (e.g., "John's iPhone").
    @MainActor
    public static var deviceName: String {
        UIDevice.current.name
    }

    /// The operating system name (e.g., "iOS", "iPadOS").
    @MainActor
    public static var systemName: String {
        UIDevice.current.systemName
    }

    /// The operating system version (e.g., "17.0").
    @MainActor
    public static var systemVersion: String {
        UIDevice.current.systemVersion
    }

    /// Full device description for logging/analytics.
    ///
    /// Example: "iPhone (iOS 17.0)"
    @MainActor
    public static var deviceDescription: String {
        "\(deviceModel) (\(systemName) \(systemVersion))"
    }
    #endif

    // MARK: - System Information

    /// Number of available processor cores.
    public static var processorCount: Int {
        ProcessInfo.processInfo.processorCount
    }

    /// Amount of physical memory in bytes.
    public static var physicalMemory: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// Amount of physical memory formatted for display (e.g., "8 GB"), localized.
    ///
    /// Equivalent to `physicalMemory.formatted(.byteCount(style: .memory))`.
    public static var physicalMemoryFormatted: String {
        physicalMemory.formatted(.byteCount(style: .memory))
    }

    /// Current locale identifier (e.g., "en_US").
    public static var localeIdentifier: String {
        Locale.current.identifier
    }

    /// Current timezone identifier (e.g., "America/New_York").
    public static var timezoneIdentifier: String {
        TimeZone.current.identifier
    }

    /// Preferred languages configured on the device.
    public static var preferredLanguages: [String] {
        Locale.preferredLanguages
    }
}
