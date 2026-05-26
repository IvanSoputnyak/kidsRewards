import CommonCrypto
import Foundation
import LocalAuthentication
import Security

protocol ParentPINManaging: Sendable {
    var hasPIN: Bool { get }
    @discardableResult
    func save(pin: String) -> Bool
    @discardableResult
    func clear() -> Bool
    func verify(pin: String) -> Bool
}

final class KeychainParentPINManager: ParentPINManaging, @unchecked Sendable {
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

    @discardableResult
    func save(pin: String) -> Bool {
        let salt = randomSalt()
        guard let hash = stretchedHash(pin: pin, salt: salt, iterations: currentIterations) else {
            return false
        }
        let nextPayload = Payload(
            version: currentVersion,
            iterations: currentIterations,
            salt: salt,
            hash: hash
        )
        guard let data = try? JSONEncoder().encode(nextPayload) else { return false }

        let query = baseQuery()
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func clear() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
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
        let hash: Data
        if payload.version >= 2 {
            guard let stretchedHash = stretchedHash(pin: pin, salt: payload.salt, iterations: iterations) else {
                return false
            }
            hash = stretchedHash
        } else {
            hash = singleHash(pin: pin, salt: payload.salt)
        }
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
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    private func singleHash(pin: String, salt: Data) -> Data {
        var input = Data()
        input.append(salt)
        input.append(Data(pin.utf8))
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        input.withUnsafeBytes { inputBytes in
            _ = CC_SHA256(inputBytes.baseAddress, CC_LONG(input.count), &digest)
        }
        return Data(digest)
    }

    private func stretchedHash(pin: String, salt: Data, iterations: Int) -> Data? {
        guard iterations > 1 else {
            return singleHash(pin: pin, salt: salt)
        }

        var derivedKey = [UInt8](repeating: 0, count: 32)
        let password = Array(pin.utf8)
        let saltBytes = Array(salt)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            password,
            password.count,
            saltBytes,
            saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            UInt32(iterations),
            &derivedKey,
            derivedKey.count
        )
        guard status == kCCSuccess else { return nil }
        return Data(derivedKey)
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

    static func unlock(reason: String, completion: @escaping (Bool, String?) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false, "Biometric unlock is not available.")
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            let message: String? = success ? nil : biometricErrorMessage(for: error)
            DispatchQueue.main.async {
                completion(success, message)
            }
        }
    }

    private static func biometricErrorMessage(for error: Error?) -> String {
        guard let error = error as? LAError else { return "Biometric unlock failed." }
        switch error.code {
        case .biometryLockout:
            return "Too many attempts. Use your device passcode to re-enable Face ID / Touch ID."
        case .userCancel, .systemCancel, .appCancel:
            return ""
        case .biometryNotEnrolled:
            return "No Face ID / Touch ID is enrolled on this device."
        case .biometryNotAvailable:
            return "Biometric unlock is not available."
        default:
            return "Biometric unlock failed."
        }
    }
}
