import CommonCrypto
import Foundation

/// A stored exit passcode.
///
/// The configuration never holds the passcode itself. What is written back is
/// this record: algorithm, iteration count, a random salt and the derived key.
/// An administrator may put a plaintext passcode into a configuration document
/// once, because typing a PBKDF2 record by hand is not a thing anyone will do;
/// the first launch replaces it in place.
///
/// Encoded form, one line, four `$`-separated fields:
///
///     pbkdf2-sha256$<iterations>$<salt base64>$<derived key base64>
public struct PasscodeRecord: Sendable, Equatable {
    public static let algorithmName = "pbkdf2-sha256"
    /// Chosen for an interactive unlock on a kiosk machine, which is often
    /// modest hardware. Measured rather than guessed; see the note in the
    /// derivation test.
    public static let defaultIterations = 310_000
    public static let saltByteCount = 16
    public static let derivedKeyByteCount = 32

    public let iterations: Int
    public let salt: Data
    public let derivedKey: Data

    public init(iterations: Int, salt: Data, derivedKey: Data) {
        self.iterations = iterations
        self.salt = salt
        self.derivedKey = derivedKey
    }

    /// Derives a record from a plaintext passcode with a fresh random salt.
    /// Returns `nil` for an empty passcode: an empty exit passcode is not a
    /// weak lock, it is no lock, and it must not be storable.
    public init?(passcode: String, iterations: Int = PasscodeRecord.defaultIterations) {
        guard !passcode.isEmpty, iterations > 0 else { return nil }
        var salt = Data(count: PasscodeRecord.saltByteCount)
        let generated = salt.withUnsafeMutableBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, base)
        }
        guard generated == errSecSuccess else { return nil }
        guard
            let derived = PasscodeRecord.derive(
                passcode: passcode,
                salt: salt,
                iterations: iterations
            )
        else { return nil }
        self.init(iterations: iterations, salt: salt, derivedKey: derived)
    }

    public init?(encoded: String) {
        let fields = encoded.split(separator: "$", omittingEmptySubsequences: false)
        guard fields.count == 4,
            fields[0] == PasscodeRecord.algorithmName,
            let iterations = Int(fields[1]), iterations > 0,
            let salt = Data(base64Encoded: String(fields[2])), !salt.isEmpty,
            let derivedKey = Data(base64Encoded: String(fields[3])), !derivedKey.isEmpty
        else { return nil }
        self.init(iterations: iterations, salt: salt, derivedKey: derivedKey)
    }

    public var encoded: String {
        [
            PasscodeRecord.algorithmName,
            String(iterations),
            salt.base64EncodedString(),
            derivedKey.base64EncodedString(),
        ].joined(separator: "$")
    }

    /// Constant-time comparison. A passcode dialog that answers faster for a
    /// wrong first character leaks the passcode one character at a time, and a
    /// kiosk is exactly the place where somebody has the time to try.
    public func matches(_ passcode: String) -> Bool {
        guard
            let candidate = PasscodeRecord.derive(
                passcode: passcode,
                salt: salt,
                iterations: iterations
            )
        else { return false }
        guard candidate.count == derivedKey.count else { return false }
        var difference: UInt8 = 0
        for (lhs, rhs) in zip(candidate, derivedKey) {
            difference |= lhs ^ rhs
        }
        return difference == 0
    }

    static func derive(passcode: String, salt: Data, iterations: Int) -> Data? {
        let passwordBytes = Array(passcode.utf8)
        var derived = Data(count: PasscodeRecord.derivedKeyByteCount)
        let status = derived.withUnsafeMutableBytes { derivedBuffer -> Int32 in
            salt.withUnsafeBytes { saltBuffer -> Int32 in
                guard let derivedBase = derivedBuffer.bindMemory(to: UInt8.self).baseAddress,
                    let saltBase = saltBuffer.bindMemory(to: UInt8.self).baseAddress
                else { return Int32(kCCParamError) }
                return CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.map { Int8(bitPattern: $0) },
                    passwordBytes.count,
                    saltBase,
                    saltBuffer.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    derivedBase,
                    derivedBuffer.count
                )
            }
        }
        return status == kCCSuccess ? derived : nil
    }
}
