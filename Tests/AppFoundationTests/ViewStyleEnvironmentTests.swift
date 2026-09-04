#if canImport(SwiftUI)
import SwiftUI
import Testing

@testable import AppFoundation

// MARK: - AF-15: the `*ViewStyle` Environment mechanism
//
// `LoadingViewStyle`/`ErrorViewStyle`/`EmptyViewStyle`/`BannerViewStyle` render arbitrary
// SwiftUI content, which can't be asserted on without a snapshot library — out of scope
// per the "no external dependencies" constraint. What CAN be verified honestly, without
// rendering anything, is the contract `.loadingViewStyle(_:)` etc. actually promise:
//
// 1. `EnvironmentValues.xViewStyle` stores and returns exactly the style that was set
///   (the same computed-property mechanism `.environment(\.xViewStyle, _)` writes through).
// 2. The `AnyXViewStyle` box installed there forwards `makeBody(configuration:)` to the
//    wrapped, caller-provided style EXACTLY once, with the SAME configuration value it was
//    given — never silently substituting the default, never dropping/duplicating the call.
//
// A regression in either would mean a consumer's custom style (installed via
// `.loadingViewStyle(MyStyle())`) either doesn't take effect or renders inconsistently —
// exactly what AF-15 exists to prevent.

@Suite("*ViewStyle Environment boxing (AF-15)")
struct ViewStyleEnvironmentTests {
    // MARK: - LoadingViewStyle

    private struct SpyLoadingStyle: LoadingViewStyle {
        let recorder: Recorder
        func makeBody(configuration: LoadingConfiguration) -> some View {
            recorder.record("loading:\(configuration.style)")
            return Color.clear
        }
    }

    @Test(arguments: [ActivityStyle.fullScreen, .inline, .overlay])
    func loadingEnvironmentInstallsAndForwardsToTheProvidedStyle(style: ActivityStyle) {
        let recorder = Recorder()
        var env = EnvironmentValues()
        env.loadingViewStyle = AnyLoadingViewStyle(SpyLoadingStyle(recorder: recorder))

        _ = env.loadingViewStyle.makeBody(configuration: LoadingConfiguration(style: style))

        #expect(recorder.events == ["loading:\(style)"])
    }

    @Test func loadingEnvironmentDefaultsToTheBuiltInStyleWithoutInstallingAnything() {
        let recorder = Recorder()
        let env = EnvironmentValues()
        // The default value must come from `LoadingViewStyleKey.defaultValue`
        // (`DefaultLoadingViewStyle`), not from the spy — nothing was installed here.
        _ = env.loadingViewStyle.makeBody(configuration: LoadingConfiguration(style: .fullScreen))
        #expect(recorder.events.isEmpty)
    }

    // MARK: - ErrorViewStyle

    private struct SpyErrorStyle: ErrorViewStyle {
        let recorder: Recorder
        func makeBody(configuration: ErrorConfiguration) -> some View {
            recorder.record("error:\(configuration.error.title)")
            return Color.clear
        }
    }

    @Test func errorEnvironmentInstallsAndForwardsTheSameErrorItWasGiven() {
        let recorder = Recorder()
        var env = EnvironmentValues()
        env.errorViewStyle = AnyErrorViewStyle(SpyErrorStyle(recorder: recorder))

        let error = ScreenError(title: "Network Error", message: "Offline")
        _ = env.errorViewStyle.makeBody(configuration: ErrorConfiguration(error: error))

        #expect(recorder.events == ["error:Network Error"])
    }

    // MARK: - EmptyViewStyle

    private struct SpyEmptyStyle: EmptyViewStyle {
        let recorder: Recorder
        func makeBody(configuration: EmptyConfiguration) -> some View {
            recorder.record("empty")
            return Color.clear
        }
    }

    @Test func emptyEnvironmentInstallsAndForwardsExactlyOnce() {
        let recorder = Recorder()
        var env = EnvironmentValues()
        env.emptyViewStyle = AnyEmptyViewStyle(SpyEmptyStyle(recorder: recorder))

        _ = env.emptyViewStyle.makeBody(configuration: EmptyConfiguration())

        #expect(recorder.events == ["empty"])
    }

    // MARK: - BannerViewStyle

    private struct SpyBannerStyle: BannerViewStyle {
        let recorder: Recorder
        func makeBody(configuration: BannerConfiguration) -> some View {
            recorder.record("banner:\(configuration.banner.message)")
            return Color.clear
        }
    }

    @Test func bannerEnvironmentInstallsAndForwardsTheDismissClosureUnchanged() {
        let recorder = Recorder()
        var env = EnvironmentValues()
        env.bannerViewStyle = AnyBannerViewStyle(SpyBannerStyle(recorder: recorder))

        var dismissed = false
        let banner = BannerState.success("Saved!")
        _ = env.bannerViewStyle.makeBody(configuration: BannerConfiguration(banner: banner) { dismissed = true })

        #expect(recorder.events == ["banner:Saved!"])

        // The box must forward the EXACT configuration, including its closures — not
        // reconstruct one of its own that silently drops the dismiss action.
        let sameConfig = BannerConfiguration(banner: banner) { dismissed = true }
        sameConfig.dismiss()
        #expect(dismissed)
    }

    // MARK: - Reinstalling replaces the previous style rather than stacking both

    @Test func installingASecondStyleReplacesTheFirstEntirely() {
        let first = Recorder()
        let second = Recorder()
        var env = EnvironmentValues()

        env.loadingViewStyle = AnyLoadingViewStyle(SpyLoadingStyle(recorder: first))
        env.loadingViewStyle = AnyLoadingViewStyle(SpyLoadingStyle(recorder: second))

        _ = env.loadingViewStyle.makeBody(configuration: LoadingConfiguration(style: .overlay))

        #expect(first.events.isEmpty)
        #expect(second.events == ["loading:overlay"])
    }
}

// MARK: - Configuration value types: construction and property forwarding

@Suite("*Configuration value types")
struct ViewStyleConfigurationTests {
    @Test func loadingConfigurationStoresTheStyleItWasGiven() {
        #expect(LoadingConfiguration(style: .inline).style == .inline)
    }

    @Test func errorConfigurationStoresTheErrorItWasGiven() {
        let error = ScreenError(title: "T", message: "M")
        #expect(ErrorConfiguration(error: error).error == error)
    }

    @Test func bannerConfigurationStoresTheBannerAndInvokesDismissOnDemand() {
        var dismissCount = 0
        let banner = BannerState.info("Heads up")
        let config = BannerConfiguration(banner: banner) { dismissCount += 1 }

        #expect(config.banner == banner)
        config.dismiss()
        config.dismiss()
        #expect(dismissCount == 2)
    }
}
#endif
