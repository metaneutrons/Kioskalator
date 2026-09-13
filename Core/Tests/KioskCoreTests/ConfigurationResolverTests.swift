import Foundation
import Testing

@testable import KioskCore

private func document(
    _ origin: ConfigurationOrigin,
    _ members: [String: ConfigurationValue]
) -> ConfigurationDocument {
    ConfigurationDocument(origin: origin, members: members)
}

@Suite("Configuration precedence")
struct ConfigurationPrecedenceTests {
    @Test("The highest-ranked layer supplying a value wins")
    func precedenceOrder() {
        let resolved = ConfigurationResolver.resolve([
            document(.user, ["homeURL": .string("https://user.example.org/")]),
            document(.file, ["homeURL": .string("https://file.example.org/")]),
            document(.managed, ["homeURL": .string("https://managed.example.org/")]),
        ])
        let setting = try? #require(resolved.setting(for: .homeURL))
        #expect(setting?.value == .string("https://managed.example.org/"))
        #expect(setting?.origin == .managed)
    }

    @Test("Order of the input array does not matter")
    func inputOrderIrrelevant() {
        let ascending = ConfigurationResolver.resolve([
            document(.managed, ["idleTimeout": .integer(10)]),
            document(.user, ["idleTimeout": .integer(20)]),
        ])
        let descending = ConfigurationResolver.resolve([
            document(.user, ["idleTimeout": .integer(20)]),
            document(.managed, ["idleTimeout": .integer(10)]),
        ])
        #expect(ascending[.idleTimeout] == descending[.idleTimeout])
        #expect(ascending[.idleTimeout] == .integer(10))
    }

    @Test("A key nobody sets falls back to its default and says so")
    func fallbackOrigin() {
        let resolved = ConfigurationResolver.resolve([])
        let setting = try? #require(resolved.setting(for: .unlockHotkey))
        #expect(setting?.value == .string("ctrl+alt+cmd+K"))
        #expect(setting?.origin == .fallback)
    }

    @Test("A key with no default resolves to no value at all")
    func keysWithoutDefault() {
        let resolved = ConfigurationResolver.resolve([])
        #expect(resolved[.homeURL] == nil)
        #expect(resolved[.exitPasscode] == nil)
    }

    @Test("Every key is either defaulted or deliberately absent")
    func everyKeyIsAccountedFor() {
        let withoutDefault: Set<ConfigurationKey> = [
            .homeURL, .userAgent, .scheduledRestartTime, .exitPasscode,
        ]
        for key in ConfigurationKey.allCases {
            #expect(
                (key.defaultValue != nil) == !withoutDefault.contains(key),
                "\(key.rawValue) disagrees with the documented default set"
            )
        }
    }

    @Test("A default that exists has the kind the key declares")
    func defaultsMatchTheirKind() {
        for key in ConfigurationKey.allCases {
            guard let value = key.defaultValue else { continue }
            #expect(value.matches(kind: key.kind), "default of \(key.rawValue) has the wrong kind")
        }
    }
}

@Suite("Locking")
struct ConfigurationLockingTests {
    @Test("A locked key refuses every lower layer, and the refusal is reported")
    func lockRefusesLowerLayers() {
        let resolved = ConfigurationResolver.resolve([
            document(
                .managed,
                [
                    "homeURL": .string("https://managed.example.org/"),
                    "locked": .array([.string("homeURL")]),
                ]),
            document(.file, ["homeURL": .string("https://file.example.org/")]),
            document(.user, ["homeURL": .string("https://user.example.org/")]),
        ])
        #expect(resolved[.homeURL] == .string("https://managed.example.org/"))
        #expect(resolved.setting(for: .homeURL)?.lockedBy == .managed)
        #expect(resolved.rejections.count == 2)
        #expect(resolved.rejections.allSatisfy { $0.key == .homeURL && $0.lockedBy == .managed })
        #expect(Set(resolved.rejections.map(\.attemptedBy)) == [.file, .user])
    }

    @Test("Counter-probe: without the lock the same layers produce no refusal")
    func withoutLockThereIsNoRejection() {
        let resolved = ConfigurationResolver.resolve([
            document(.managed, ["homeURL": .string("https://managed.example.org/")]),
            document(.file, ["homeURL": .string("https://file.example.org/")]),
            document(.user, ["homeURL": .string("https://user.example.org/")]),
        ])
        #expect(resolved[.homeURL] == .string("https://managed.example.org/"))
        #expect(resolved.setting(for: .homeURL)?.lockedBy == nil)
        #expect(resolved.rejections.isEmpty)
        #expect(resolved.setting(for: .homeURL)?.isEditableFromSettings == true)
    }

    @Test("A lock without a value adopts the next value down and freezes it there")
    func lockWithoutValueAdoptsTheLayerBelow() {
        let resolved = ConfigurationResolver.resolve([
            document(.managed, ["locked": .array([.string("homeURL")])]),
            document(.file, ["homeURL": .string("https://file.example.org/")]),
            document(.user, ["homeURL": .string("https://user.example.org/")]),
        ])
        let setting = try? #require(resolved.setting(for: .homeURL))
        #expect(setting?.value == .string("https://file.example.org/"))
        #expect(setting?.origin == .file)
        #expect(setting?.lockedBy == .file)
        #expect(resolved.rejections.map(\.attemptedBy) == [.user])
    }

    @Test("A locked capability cannot be switched back on from below")
    func lockedCapabilityStaysOff() {
        let resolved = ConfigurationResolver.resolve([
            document(
                .managed,
                [
                    "allowFileUploads": .boolean(false),
                    "locked": .array([.string("allowFileUploads")]),
                ]),
            document(.user, ["allowFileUploads": .boolean(true)]),
        ])
        #expect(resolved[.allowFileUploads] == .boolean(false))
        #expect(resolved.setting(for: .allowFileUploads)?.isEditableFromSettings == false)
    }

    @Test("A lock on a key nobody sets freezes the built-in default")
    func lockOnAnUnsetKeyFreezesTheDefault() {
        let resolved = ConfigurationResolver.resolve([
            document(.managed, ["locked": .array([.string("clipboardEnabled")])])
        ])
        let setting = try? #require(resolved.setting(for: .clipboardEnabled))
        #expect(setting?.value == .boolean(true))
        #expect(setting?.origin == .fallback)
        #expect(setting?.isEditableFromSettings == false)
    }
}

@Suite("Document parsing")
struct ConfigurationDocumentTests {
    @Test("An unknown key is reported with its layer, not discarded")
    func unknownKeyIsReported() {
        let parsed = document(.file, ["homeUrl": .string("https://example.org/")])
        #expect(parsed.values.isEmpty)
        #expect(parsed.defects == [.unknownKey(name: "homeUrl", origin: .file)])
    }

    @Test("A value of the wrong kind is rejected and named")
    func wrongKindIsReported() {
        let parsed = document(.managed, ["idleTimeout": .string("300")])
        #expect(parsed.values.isEmpty)
        #expect(
            parsed.defects == [
                .wrongKind(key: .idleTimeout, origin: .managed, expected: .integer)
            ]
        )
    }

    @Test("Counter-probe: the same key with the right kind is accepted")
    func rightKindIsAccepted() {
        let parsed = document(.managed, ["idleTimeout": .integer(300)])
        #expect(parsed.values[.idleTimeout] == .integer(300))
        #expect(parsed.defects.isEmpty)
    }

    @Test("Every defect is collected, not only the first")
    func defectsAccumulate() {
        let parsed = document(
            .file,
            [
                "homeUrl": .string("https://example.org/"),
                "idleTimeout": .string("300"),
                "locked": .array([.string("nonsense")]),
            ])
        #expect(parsed.defects.count == 3)
    }

    @Test("A malformed lock declaration is a defect, not a silent absence")
    func malformedLockDeclaration() {
        let parsed = document(.file, ["locked": .string("homeURL")])
        #expect(parsed.locks.isEmpty)
        #expect(parsed.defects == [.malformedLockDeclaration(origin: .file)])
    }

    @Test("A mistyped element makes the whole string array invalid")
    func stringArrayIsAllOrNothing() {
        let parsed = document(
            .file,
            [
                "allowedURLPatterns": .array([.string("a.example.org/*"), .integer(7)])
            ])
        #expect(parsed.values[.allowedURLPatterns] == nil)
        #expect(parsed.defects.count == 1)
    }

    @Test("Invalid JSON is reported rather than read as an empty configuration")
    func invalidJSONIsReported() {
        let data = Data(#"{"homeURL": "https://example.org/"#.utf8)
        let parsed = ConfigurationSources.document(origin: .remote, json: data)
        #expect(parsed.values.isEmpty)
        guard parsed.defects.count == 1, case .unreadableDocument(let origin, _) = parsed.defects[0]
        else {
            Issue.record("expected exactly one unreadableDocument defect, got \(parsed.defects)")
            return
        }
        #expect(origin == .remote)
    }

    @Test("Counter-probe: the same document with the comma removed parses")
    func validJSONParses() {
        let data = Data(#"{"homeURL": "https://example.org/"}"#.utf8)
        let parsed = ConfigurationSources.document(origin: .remote, json: data)
        #expect(parsed.values[.homeURL] == .string("https://example.org/"))
        #expect(parsed.defects.isEmpty)
    }

    @Test("A managed boolean arrives as a boolean, not as 0 or 1")
    func propertyListBooleansKeepTheirType() {
        let value = try? #require(ConfigurationValue(propertyList: NSNumber(value: true)))
        #expect(value == .boolean(true))
        // Counter-probe: the integer 1 must not come back as a boolean, or the
        // distinction the boolean branch exists for would be untested.
        let integer = try? #require(ConfigurationValue(propertyList: NSNumber(value: 1)))
        #expect(integer == .integer(1))
    }
}
