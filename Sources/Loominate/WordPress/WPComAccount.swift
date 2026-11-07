import Foundation

/// Non-secret facts about the signed-in WordPress.com account. The token itself lives in the Keychain.
struct WPComAccount: Codable, Equatable {
    var blogID: Int
    var blogURL: String
    var scope: String
    var userLogin: String
    var displayName: String
    var signedInAt: Date

    private static let defaultsKey = "wpcom.account.v1"

    static func load() -> WPComAccount? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(WPComAccount.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: WPComAccount.defaultsKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    var label: String {
        displayName.isEmpty ? userLogin : "\(displayName) (\(userLogin))"
    }
}
