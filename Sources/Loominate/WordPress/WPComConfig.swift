import Foundation

/// Where recordings go and how the app identifies itself to WordPress.com.
enum WPComConfig {
    /// WordPress.com OAuth app "Loominate" (owner a8cuser + natecallen).
    static let clientID = "152440"
    /// specialprojects.automattic.com (a8cspcooltools.wordpress.com)
    static let blogID = 236976534
    static let siteURL = URL(string: "https://specialprojects.automattic.com")!
    static let siteName = "Automattic Special Projects"

    static let apiBase = URL(string: "https://public-api.wordpress.com")!
    static let authorizeURL = URL(string: "https://public-api.wordpress.com/oauth2/authorize")!
    static let tokenURL = URL(string: "https://public-api.wordpress.com/oauth2/token")!

    static let callbackPort: UInt16 = 52631
    /// Must match one of the redirect URLs registered on the OAuth app, byte for byte.
    static let redirectURI = "http://127.0.0.1:52631/callback"

    static let keychainService = "com.automattic.loominate.wpcom"
    static let infoPlistSecretKey = "LoominateWPComClientSecret"

    /// Injected into the built app's Info.plist by Scripts/bundle.sh; never in the repo.
    static var clientSecret: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: infoPlistSecretKey) as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    static var hasClientSecret: Bool { clientSecret != nil }

    /// CLI and notification features need the real bundle (Info.plist, stable code identity).
    static var isRunningFromBundle: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static func shareURL(guid: String) -> URL {
        URL(string: "https://videopress.com/v/\(guid)")!
    }
}
