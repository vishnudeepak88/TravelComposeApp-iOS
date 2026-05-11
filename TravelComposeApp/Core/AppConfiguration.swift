import Foundation

// MARK: - Capability flags
//
// Some iOS capabilities (Sign in with Apple, Push Notifications,
// Live Activities) require paid Apple Developer Program entitlements.
// The Personal Team free Apple ID this pilot uses can't enable them.
// Rather than scatter `#if` blocks across feature views, we centralise
// the flags here. Flip to `true` once the team upgrades — and the
// corresponding entitlements file gets re-linked in pbxproj.
enum AppCapabilities {
    /// Sign in with Apple. Requires `com.apple.developer.applesignin`
    /// entitlement + paid team membership. Personal Team accounts
    /// (free Apple ID) can't enable this — the SignInWithAppleButton
    /// would compile but fail at sign-in. Wire is in code; flip the
    /// flag when the team supports it.
    static let signInWithAppleAvailable: Bool = false

    /// Push notifications via APNs. Requires `aps-environment`
    /// entitlement + paid team membership. APNs token registration
    /// (`PushRegistration.swift`) silently no-ops when this is off.
    static let pushNotificationsAvailable: Bool = false

    /// Live Activities (Lock Screen / Dynamic Island ride status).
    /// Requires a Widget Extension target + ActivityKit framework.
    /// Phase-2 work.
    static let liveActivitiesAvailable: Bool = false
}

enum AppConfiguration {
    static let apiBaseURLOverrideKey = "voygo.api.baseURL.override"
    private static let bundleAPIBaseURLKey = "VOYGO_API_BASE_URL"

    static var apiBaseURL: URL {
        if let override = UserDefaults.standard.string(forKey: apiBaseURLOverrideKey),
           let url = URL(string: override), !override.isEmpty {
            return url
        }

        if let bundled = Bundle.main.object(forInfoDictionaryKey: bundleAPIBaseURLKey) as? String,
           let url = URL(string: bundled), !bundled.isEmpty {
            return url
        }

        // Compile-time constant URL — fatal in DEBUG (programmer typo
        // would crash early), graceful `about:blank` in release. See
        // SafeURL.swift for the helper.
        return URL.staticURL("https://voygo-ios-api.onrender.com/")
    }

    static func setAPIBaseURLOverride(_ url: URL?) {
        if let url {
            UserDefaults.standard.set(url.absoluteString, forKey: apiBaseURLOverrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: apiBaseURLOverrideKey)
        }
    }
}
