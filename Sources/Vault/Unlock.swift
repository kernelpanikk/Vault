import Foundation
import LocalAuthentication
import Security

// shortcut: login-keychain item gated by LAContext, because the data-protection keychain with
// biometryCurrentSet returns -34018 on an ad-hoc signed app. Switch once signed with an Apple ID team.
enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Vault",
        kSecAttrAccount as String: "master",
    ]

    static func save(_ password: String) {
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrSynchronizable as String] = false
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

enum Biometrics {
    static var available: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Usa password"
        return (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                  localizedReason: "sbloccare l'archivio")) ?? false
    }
}
