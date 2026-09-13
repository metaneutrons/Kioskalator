import Foundation
import Testing

@testable import KioskCore

@Suite("Time of day")
struct TimeOfDayTests {
    @Test("A well-formed time parses and prints back the same way")
    func roundTrip() throws {
        let time = try #require(TimeOfDay(text: "03:05"))
        #expect(time.hour == 3)
        #expect(time.minute == 5)
        #expect(time.description == "03:05")
    }

    @Test(
        "Anything the operator could have meant two ways is refused",
        arguments: ["3:05", "03:5", "24:00", "23:60", "0305", "03:05:00", "", "ab:cd", "-1:00"]
    )
    func strictParsing(_ text: String) {
        #expect(TimeOfDay(text: text) == nil, "'\(text)' should not parse")
    }

    @Test("Boundary times are valid")
    func boundaries() {
        #expect(TimeOfDay(text: "00:00") != nil)
        #expect(TimeOfDay(text: "23:59") != nil)
    }

    @Test("Times order by clock position")
    func ordering() throws {
        #expect(try #require(TimeOfDay(text: "03:05")) < (try #require(TimeOfDay(text: "03:06"))))
        #expect(try #require(TimeOfDay(text: "03:59")) < (try #require(TimeOfDay(text: "04:00"))))
    }

    @Test("The next occurrence is strictly in the future and carries the right clock time")
    func nextOccurrence() throws {
        var calendar = Calendar(identifier: .gregorian)
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        calendar.timeZone = zone

        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 13
        components.hour = 10
        components.minute = 0
        let now = try #require(calendar.date(from: components))

        let time = try #require(TimeOfDay(text: "03:00"))
        let next = try #require(time.nextOccurrence(after: now, calendar: calendar))
        #expect(next > now)

        let parts = calendar.dateComponents([.hour, .minute, .day], from: next)
        #expect(parts.hour == 3)
        #expect(parts.minute == 0)
        #expect(parts.day == 14, "03:00 after 10:00 is tomorrow, not today")
    }

    @Test("A time later today comes before tomorrow")
    func laterToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 13
        components.hour = 10
        let now = try #require(calendar.date(from: components))

        let time = try #require(TimeOfDay(text: "22:30"))
        let next = try #require(time.nextOccurrence(after: now, calendar: calendar))
        #expect(calendar.dateComponents([.day], from: next).day == 13)
    }
}
