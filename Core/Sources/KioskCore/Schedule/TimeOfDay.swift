import Foundation

/// A local wall-clock time, `HH:mm` in 24-hour form.
///
/// Deliberately not a `Date`: a scheduled restart at 03:00 means 03:00 wherever
/// the kiosk stands, including on the two days a year when that hour is skipped
/// or repeated. Resolving it against the calendar at the moment it is needed is
/// what makes that work; a `Date` computed once at launch does not.
public struct TimeOfDay: Sendable, Equatable, Comparable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int

    public init?(hour: Int, minute: Int) {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// Parses `HH:mm`. Strict on purpose: `7:5` and `25:00` are rejected rather
    /// than guessed at, because a schedule that silently means something else
    /// than it says is discovered when the kiosk restarts during opening hours.
    public init?(text: String) {
        let fields = text.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 2,
            fields[0].count == 2, fields[1].count == 2,
            fields.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
            let hour = Int(fields[0]), let minute = Int(fields[1])
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    public var description: String { String(format: "%02d:%02d", hour, minute) }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    /// The next moment this time of day occurs strictly after `date`.
    ///
    /// `nextDate(after:matching:)` with `.nextTime` skips a time that does not
    /// exist on a spring-forward day instead of returning a moment that never
    /// happens, which is the behaviour a restart schedule wants.
    public func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(
            after: date,
            matching: DateComponents(hour: hour, minute: minute),
            matchingPolicy: .nextTime,
            direction: .forward
        )
    }
}
