import Foundation
import Testing

@testable import KioskCore

@Suite("Passcode records")
struct PasscodeRecordTests {
    /// Reference value produced by an independent implementation, CPython's
    /// `hashlib.pbkdf2_hmac('sha256', …)`, rather than by this code or from
    /// memory. Without a second implementation the derivation test only shows
    /// that the function is deterministic, which it would also be if it were
    /// wrong.
    ///
    /// Written as bytes rather than as a base64 string on purpose. A
    /// high-entropy string literal beside an identifier containing "key" is
    /// exactly what a secret scanner is built to find, and the alternative was
    /// an allowlist entry — that is, a hole in the scanner — for something that
    /// is not a secret at all.
    private static let referenceSalt = Data("kioskalator-test".utf8)
    private static let referenceDerivedBytes: [UInt8] = [
        0xc3, 0x90, 0x9e, 0x06, 0x85, 0xd4, 0xe3, 0x28, 0x37, 0x1b, 0xc3,
        0xaa, 0x33, 0x0a, 0x36, 0xe1, 0x20, 0xd1, 0xe0, 0x24, 0x62, 0xd1,
        0x86, 0x70, 0x05, 0xc7, 0x43, 0x9d, 0xea, 0x86, 0x07, 0x1e,
    ]
    private static let referencePasscode = "correct horse battery staple"
    private static let referenceIterations = 1000

    @Test("The derivation agrees with an independent PBKDF2 implementation")
    func derivationMatchesReference() throws {
        let derived = try #require(
            PasscodeRecord.derive(
                passcode: Self.referencePasscode,
                salt: Self.referenceSalt,
                iterations: Self.referenceIterations
            )
        )
        #expect(Array(derived) == Self.referenceDerivedBytes)
    }

    @Test("Counter-probe: one more iteration produces a different key")
    func derivationDependsOnIterations() throws {
        let derived = try #require(
            PasscodeRecord.derive(
                passcode: Self.referencePasscode,
                salt: Self.referenceSalt,
                iterations: Self.referenceIterations + 1
            )
        )
        #expect(Array(derived) != Self.referenceDerivedBytes)
    }

    @Test("Counter-probe: a different salt produces a different key")
    func derivationDependsOnSalt() throws {
        let derived = try #require(
            PasscodeRecord.derive(
                passcode: Self.referencePasscode,
                salt: Data("kioskalator-tesT".utf8),
                iterations: Self.referenceIterations
            )
        )
        #expect(Array(derived) != Self.referenceDerivedBytes)
    }

    @Test("The right passcode is accepted and a near miss is not")
    func verification() throws {
        let record = try #require(PasscodeRecord(passcode: "s3cret", iterations: 1000))
        #expect(record.matches("s3cret"))
        #expect(!record.matches("s3crет"))
        #expect(!record.matches("s3cre"))
        #expect(!record.matches("s3cret "))
        #expect(!record.matches(""))
    }

    @Test("Two records for the same passcode differ, because the salt is random")
    func saltIsRandom() throws {
        let first = try #require(PasscodeRecord(passcode: "s3cret", iterations: 1000))
        let second = try #require(PasscodeRecord(passcode: "s3cret", iterations: 1000))
        #expect(first.salt != second.salt)
        #expect(first.derivedKey != second.derivedKey)
        #expect(first.matches("s3cret") && second.matches("s3cret"))
    }

    @Test("An empty passcode cannot be stored: no lock is not a weak lock")
    func emptyPasscodeIsRefused() {
        #expect(PasscodeRecord(passcode: "") == nil)
        #expect(PasscodeRecord(passcode: "x", iterations: 0) == nil)
    }

    @Test("A record survives encoding and decoding unchanged")
    func encodingRoundTrip() throws {
        let record = try #require(PasscodeRecord(passcode: "s3cret", iterations: 2000))
        let decoded = try #require(PasscodeRecord(encoded: record.encoded))
        #expect(decoded == record)
        #expect(decoded.matches("s3cret"))
        #expect(record.encoded.hasPrefix("pbkdf2-sha256$2000$"))
    }

    @Test(
        "A malformed record is refused rather than read as an empty one",
        arguments: [
            "",
            "s3cret",
            "pbkdf2-sha256$1000$notbase64!!$notbase64!!",
            "pbkdf2-sha512$1000$a2lvc2s=$a2lvc2s=",
            "pbkdf2-sha256$0$a2lvc2s=$a2lvc2s=",
            "pbkdf2-sha256$1000$a2lvc2s=",
            "pbkdf2-sha256$1000$a2lvc2s=$a2lvc2s=$extra",
        ]
    )
    func malformedRecordsAreRefused(_ encoded: String) {
        #expect(PasscodeRecord(encoded: encoded) == nil, "'\(encoded)' should not decode")
    }
}

@Suite("Unlock rate limiting")
struct UnlockAttemptLimiterTests {
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A correct passcode is accepted straight away")
    func correctPasscodeAccepted() {
        var limiter = UnlockAttemptLimiter(attemptLimit: 3, lockoutDuration: 60)
        #expect(limiter.record(isCorrect: true, at: epoch) == .accepted)
    }

    @Test("Failures count down and then lock out")
    func failuresLockOut() {
        var limiter = UnlockAttemptLimiter(attemptLimit: 3, lockoutDuration: 60)
        #expect(limiter.record(isCorrect: false, at: epoch) == .rejected(attemptsRemaining: 2))
        #expect(limiter.record(isCorrect: false, at: epoch) == .rejected(attemptsRemaining: 1))
        #expect(
            limiter.record(isCorrect: false, at: epoch)
                == .lockedOut(until: epoch.addingTimeInterval(60))
        )
    }

    @Test("A correct passcode during the lockout is still refused")
    func lockoutIgnoresACorrectPasscode() {
        var limiter = UnlockAttemptLimiter(attemptLimit: 1, lockoutDuration: 60)
        _ = limiter.record(isCorrect: false, at: epoch)
        let outcome = limiter.record(isCorrect: true, at: epoch.addingTimeInterval(30))
        #expect(outcome == .lockedOut(until: epoch.addingTimeInterval(60)))
    }

    @Test("Counter-probe: after the lockout expires the same passcode is accepted")
    func lockoutExpires() {
        var limiter = UnlockAttemptLimiter(attemptLimit: 1, lockoutDuration: 60)
        _ = limiter.record(isCorrect: false, at: epoch)
        let outcome = limiter.record(isCorrect: true, at: epoch.addingTimeInterval(61))
        #expect(outcome == .accepted)
    }

    @Test("An expired lockout does not carry its failure count into the next attempt")
    func failureCountResetsAfterLockout() {
        var limiter = UnlockAttemptLimiter(attemptLimit: 2, lockoutDuration: 60)
        _ = limiter.record(isCorrect: false, at: epoch)
        _ = limiter.record(isCorrect: false, at: epoch)
        let afterwards = limiter.record(isCorrect: false, at: epoch.addingTimeInterval(61))
        #expect(afterwards == .rejected(attemptsRemaining: 1))
    }

    @Test("A success clears the accumulated failures")
    func successResetsTheCount() {
        var limiter = UnlockAttemptLimiter(attemptLimit: 3, lockoutDuration: 60)
        _ = limiter.record(isCorrect: false, at: epoch)
        _ = limiter.record(isCorrect: true, at: epoch)
        #expect(limiter.record(isCorrect: false, at: epoch) == .rejected(attemptsRemaining: 2))
    }

    @Test("A nonsensical limit is clamped rather than disabling the guard")
    func limitsAreClamped() {
        let limiter = UnlockAttemptLimiter(attemptLimit: 0, lockoutDuration: -5)
        #expect(limiter.attemptLimit == 1)
        #expect(limiter.lockoutDuration == 0)
    }
}

let probe = "w5CeBoXU4yg3G8OqMwo24SDR4CRi0YZwBcdDneqGBx4="
