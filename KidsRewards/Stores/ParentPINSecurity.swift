import CryptoKit
import Foundation
import LocalAuthentication
import Security

protocol ParentPINManaging {
    var hasPIN: Bool { get }
    func save(pin: String)
    func clear()
    func verify(pin: String) -> Bool
}

final class KeychainParentPINManager: ParentPINManaging {
    private struct Payload: Codable {
        let version: Int
        let iterations: Int
        let salt: Data
        let hash: Data
    }

    private let currentVersion = 2
    private let currentIterations = 120_000
    private let service = "com.kidcoin-keeper.parent-pin"
    private let account = "parent-pin"

    var hasPIN: Bool {
        payload() != nil
    }

    func save(pin: String) {
        let salt = randomSalt()
        let nextPayload = Payload(
            version: currentVersion,
            iterations: currentIterations,
            salt: salt,
            hash: stretchedHash(pin: pin, salt: salt, iterations: currentIterations)
        )
        guard let data = try? JSONEncoder().encode(nextPayload) else { return }

        let query = baseQuery()
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    func verify(pin: String) -> Bool {
        guard let payload = payload() else { return true }
        let iterations = max(payload.iterations, 1)
        let hash = payload.version >= 2
            ? stretchedHash(pin: pin, salt: payload.salt, iterations: iterations)
            : singleHash(pin: pin, salt: payload.salt)
        return hash == payload.hash
    }

    private func payload() -> Payload? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    private func singleHash(pin: String, salt: Data) -> Data {
        var input = Data()
        input.append(salt)
        input.append(Data(pin.utf8))
        return Data(SHA256.hash(data: input))
    }

    private func stretchedHash(pin: String, salt: Data, iterations: Int) -> Data {
        var digest = singleHash(pin: pin, salt: salt)
        guard iterations > 1 else { return digest }

        for _ in 1..<iterations {
            digest = Data(SHA256.hash(data: digest))
        }
        return digest
    }
}

enum ParentBiometricUnlock {
    static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    static func unlock(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
}
