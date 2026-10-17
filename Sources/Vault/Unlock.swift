import CryptoKit
import Foundation
import LocalAuthentication

/// The master password, sealed (HPKE) to a Secure Enclave key that only works after Touch ID.
/// No Keychain involved: no system prompts, and the private key never leaves the chip.
enum TouchID {
    private static let url = Vault.standard.dir.appending(path: "touchid")
    private static let suite = HPKE.Ciphersuite.P256_SHA256_AES_GCM_256
    private static let info = Data("vault".utf8)

    static var available: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
            && FileManager.default.fileExists(atPath: url.path)
    }

    static func save(_ password: String) {
        guard LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil),
              let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                           [.privateKeyUsage, .biometryCurrentSet], nil),
              let key = try? SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access),
              var sender = try? HPKE.Sender(recipientKey: key.publicKey, ciphersuite: suite, info: info),
              let sealed = try? sender.seal(Data(password.utf8)),
              let data = try? PropertyListEncoder().encode([key.dataRepresentation, sender.encapsulatedKey, sealed])
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// One Touch ID prompt. nil if cancelled, failed, or the enrolled fingerprints changed.
    static func load() async -> String? {
        let context = LAContext()
        context.localizedFallbackTitle = "Usa password"
        guard (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                 localizedReason: "sbloccare l'archivio")) == true,
              let data = try? Data(contentsOf: url),
              let parts = try? PropertyListDecoder().decode([Data].self, from: data), parts.count == 3,
              let key = try? SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: parts[0], authenticationContext: context),
              var recipient = try? HPKE.Recipient(privateKey: key, ciphersuite: suite, info: info, encapsulatedKey: parts[1]),
              let plain = try? recipient.open(parts[2])
        else { return nil }
        return String(decoding: plain, as: UTF8.self)
    }
}
