import Foundation
import Security

struct StoredSession: Codable, Equatable {
    var accessToken: String
    var expiry: Date
    /// Treat tokens as expired 60 s early so we never connect with one about to die.
    var isValid: Bool { expiry.timeIntervalSinceNow > 60 }
}

/// Keeps the Spotify access token in the Keychain (device-only, after first unlock).
/// If the Keychain refuses (it can on some re-signed sideloads), the app still works for
/// the current run; you just sign in again next launch.
final class KeychainStore {
    private let service: String
    private let account = "spotify.session"

    init(service: String = Bundle.main.bundleIdentifier ?? "needle") {
        self.service = service
    }

    @discardableResult
    func saveSession(_ session: StoredSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }
        SecItemDelete(baseQuery() as CFDictionary)
        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    func loadSession() -> StoredSession? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    func deleteSession() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
