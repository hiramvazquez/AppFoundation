import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

/// Provides information about the current runtime environment.
///
/// Use this struct to detect the environment your app is running in,
/// get app metadata, and conditionally enable features based on build type.
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
public nonisolated struct AppEnvironment {

    // MARK: - Environment Detection

    /// Detects if the app is running in test or preview mode.
    ///
    /// Returns `true` when:
    /// - Running unit/UI tests (XCTestCase detected)
    /// - Running in Xcode Previews
    public static var isTestOrPreview: Bool {
        if NSClassFromString("XCTestCase") != nil {
            return true
        }
        return ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

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

    /// Amount of physical memory formatted as string (e.g., "8 GB").
    public static var physicalMemoryFormatted: String {
        let bytes = Double(physicalMemory)
        let gigabytes = bytes / 1_073_741_824 // 1024^3
        return String(format: "%.0f GB", gigabytes)
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

    // MARK: - Debug Information

    #if DEBUG
    /// Returns a dictionary with all environment information.
    ///
    /// Useful for debugging and logging.
    @MainActor
    public static var debugInfo: [String: Any] {
        var info: [String: Any] = [
            "appName": appName,
            "appVersion": appVersion,
            "buildNumber": buildNumber,
            "bundleIdentifier": bundleIdentifier,
            "isDebug": isDebug,
            "isTestFlight": isTestFlight,
            "isSimulator": isSimulator,
            "processorCount": processorCount,
            "physicalMemory": physicalMemoryFormatted,
            "locale": localeIdentifier,
            "timezone": timezoneIdentifier
        ]

        #if canImport(UIKit)
        info["deviceModel"] = deviceModel
        info["systemName"] = systemName
        info["systemVersion"] = systemVersion
        #endif

        return info
    }

    /// Prints all environment information to the console.
    @MainActor
    public static func printDebugInfo() {
        let lines = debugInfo.sorted(by: { $0.key < $1.key })
            .map { "  \($0.key): \($0.value)" }
            .joined(separator: "\n")
        AppFoundationLogger.environment.info("App Environment:\n\(lines, privacy: .private)")
    }
    #endif
}
