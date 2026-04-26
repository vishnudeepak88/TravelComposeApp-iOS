import Foundation

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

        return URL(string: "https://voygo-ios-api.onrender.com/")!
    }

    static func setAPIBaseURLOverride(_ url: URL?) {
        if let url {
            UserDefaults.standard.set(url.absoluteString, forKey: apiBaseURLOverrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: apiBaseURLOverrideKey)
        }
    }
}
