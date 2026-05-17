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

        init(version: Int = 1, iterations: Int = 1, salt: Data, hash: Data) {
            self.version = version
            self.iterations = iterations
            self.salt = salt
            self.hash = hash
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            iterations = try container.decodeIfPresent(Int.self, forKey: .iterations) ?? 1
            salt = try container.decode(Data.self, forKey: .salt)
            hash = try container.decode(Data.self, forKey: .hash)
        }
    }

    private enum PayloadLookup {
        case missing
        case invalid
        case found(Payload)
    }

    private let currentVersion = 2
    private let currentIterations = 120_000
    private let service: String
    private let account: String

    init(service: String = "com.kidcoin-keeper.parent-pin", account: String = "parent-pin") {
        self.service = service
        self.account = account
    }

    var hasPIN: Bool {
        switch payloadLookup() {
        case .missing:
            return false
        case .invalid, .found:
            return true
        }
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
        let payload: Payload
        switch payloadLookup() {
        case .missing:
            return true
        case .invalid:
            return false
        case .found(let savedPayload):
            payload = savedPayload
        }

        let iterations = max(payload.iterations, 1)
        let hash = payload.version >= 2
            ? stretchedHash(pin: pin, salt: payload.salt, iterations: iterations)
            : singleHash(pin: pin, salt: payload.salt)
        return secureCompare(hash, payload.hash)
    }

    private func payloadLookup() -> PayloadLookup {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { return .missing }
        guard status == errSecSuccess, let data = item as? Data else {
            return .invalid
        }
        do {
            return .found(try JSONDecoder().decode(Payload.self, from: data))
        } catch {
            return .invalid
        }
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

    private func secureCompare(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
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
