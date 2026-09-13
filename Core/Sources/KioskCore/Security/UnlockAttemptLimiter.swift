import Foundation

/// Rate limits passcode attempts.
///
/// The kiosk is the one place where an attacker has unlimited time in front of
/// the keyboard, so an unlimited retry loop makes the passcode length the only
/// defence. The limiter is deliberately a pure value type driven by an injected
/// clock: a lockout is only testable if time can be moved.
public struct UnlockAttemptLimiter: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case accepted
        case rejected(attemptsRemaining: Int)
        /// Locked out until the given instant.
        case lockedOut(until: Date)
    }

    public let attemptLimit: Int
    public let lockoutDuration: TimeInterval

    private var failureCount = 0
    private var lockedUntil: Date?

    public init(attemptLimit: Int, lockoutDuration: TimeInterval) {
        self.attemptLimit = max(1, attemptLimit)
        self.lockoutDuration = max(0, lockoutDuration)
    }

    /// Whether a lockout is in force at `now`, and until when.
    public func lockout(at now: Date) -> Date? {
        guard let lockedUntil, lockedUntil > now else { return nil }
        return lockedUntil
    }

    /// Records an attempt. `isCorrect` comes from the passcode record; the
    /// limiter never sees the passcode itself.
    public mutating func record(isCorrect: Bool, at now: Date) -> Outcome {
        if let until = lockout(at: now) {
            return .lockedOut(until: until)
        }
        // A lockout that has expired is cleared before the attempt is counted,
        // otherwise the first attempt after a lockout inherits its predecessor's
        // failure count and locks out again immediately.
        if lockedUntil != nil {
            lockedUntil = nil
            failureCount = 0
        }

        guard isCorrect else {
            failureCount += 1
            if failureCount >= attemptLimit {
                let until = now.addingTimeInterval(lockoutDuration)
                lockedUntil = until
                return .lockedOut(until: until)
            }
            return .rejected(attemptsRemaining: attemptLimit - failureCount)
        }

        failureCount = 0
        lockedUntil = nil
        return .accepted
    }
}
