import Foundation
import Security

/// Small string secrets in the iOS Keychain. Source credentials (tokens, passwords) live here
/// and nowhere else: not in Firestore, UserDefaults, files or logs.
final class KeychainManager {
    static let shared = KeychainManager()

    /// When an item can be read.
    enum Accessibility {
        /// Only while the device is unlocked (the default).
        case whenUnlocked
        /// After the first unlock since boot, so background playback and downloads can use it
        /// while the phone is locked. Still never synced off this device.
        case afterFirstUnlock

        var attribute: CFString {
            switch self {
            case .whenUnlocked:
                return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            case .afterFirstUnlock:
                return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
        }
    }

    private let service = "com.mp3player.keychain"

    private init() {}

    func store(_ value: String, for key: String) -> Bool {
        store(value, for: key, accessibility: .whenUnlocked)
    }

    func store(_ value: String, for key: String, accessibility: Accessibility) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: accessibility.attribute
        ]

        return SecItemAdd(addQuery as CFDictionary, nil) == noErr
    }

    func retrieve(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == noErr, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func delete(for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        return SecItemDelete(query as CFDictionary) == noErr
    }
}
