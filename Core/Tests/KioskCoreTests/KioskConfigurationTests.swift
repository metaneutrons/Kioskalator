import Foundation
import Testing

@testable import KioskCore

@Suite("Typed configuration")
struct KioskConfigurationTests {
    private func configuration(
        _ members: [String: ConfigurationValue],
        origin: ConfigurationOrigin = .file
    ) -> KioskConfiguration {
        KioskConfiguration(documents: [ConfigurationDocument(origin: origin, members: members)])
    }

    @Test("An unconfigured kiosk has no home URL rather than a blank one")
    func missingHomeURL() {
        #expect(configuration([:]).homeURL == nil)
    }

    @Test("A home URL without a scheme is refused, not silently prefixed")
    func homeURLNeedsAScheme() {
        #expect(configuration(["homeURL": .string("example.org")]).homeURL == nil)
        #expect(configuration(["homeURL": .string("https://example.org/")]).homeURL != nil)
    }

    @Test("Defaults come from the key definition, not from the accessor")
    func defaultsAreSingleSourced() {
        let empty = configuration([:])
        #expect(empty.displayMode == .allDisplays)
        #expect(empty.sessionPersistence == .persistent)
        #expect(empty.externalSchemePolicy == .block)
        #expect(empty.idleAction == .returnHome)
        #expect(empty.clipboardEnabled)
        #expect(empty.preventSleep)
        #expect(empty.reloadsOnContentProcessTermination)
        #expect(!empty.allowDownloads)
        #expect(!empty.allowFileUploads)
        #expect(!empty.allowPopups)
        #expect(!empty.showNavigationBar)
        #expect(empty.navigationBarButtons == [.back, .reload, .home])
    }

    @Test("An unrecognised enumeration value falls back rather than crashing")
    func unknownEnumerationValue() {
        let configuration = configuration(["displayMode": .string("everywhere")])
        #expect(configuration.displayMode == .allDisplays)
    }

    @Test("Zero and negative idle timeouts both mean off")
    func idleTimeoutOff() {
        #expect(configuration(["idleTimeout": .integer(0)]).idleTimeout == nil)
        #expect(configuration(["idleTimeout": .integer(-30)]).idleTimeout == nil)
        #expect(configuration(["idleTimeout": .integer(300)]).idleTimeout == 300)
    }

    @Test("The escape hatch needs a passcode, not only a switch")
    func unlockNeedsAPasscode() throws {
        #expect(!configuration([:]).unlockAvailable)
        #expect(!configuration(["unlockEnabled": .boolean(true)]).unlockAvailable)

        let record = try #require(PasscodeRecord(passcode: "s3cret", iterations: 1000))
        let withPasscode = configuration(["exitPasscode": .string(record.encoded)])
        #expect(withPasscode.unlockAvailable)
        #expect(withPasscode.passcodeRecord == record)

        let switchedOff = configuration([
            "exitPasscode": .string(record.encoded),
            "unlockEnabled": .boolean(false),
        ])
        #expect(!switchedOff.unlockAvailable)
    }

    @Test("A plaintext passcode left in the configuration is not a usable record")
    func plaintextPasscodeIsNotARecord() {
        #expect(configuration(["exitPasscode": .string("s3cret")]).passcodeRecord == nil)
        #expect(!configuration(["exitPasscode": .string("s3cret")]).unlockAvailable)
    }

    @Test("A display without an override falls back to the home URL")
    func displayOverrides() throws {
        let configuration = configuration([
            "homeURL": .string("https://home.example.org/"),
            "displayURLOverrides": .dictionary([
                "display-2": .string("https://second.example.org/")
            ]),
        ])
        #expect(configuration.url(forDisplay: "display-2")?.host() == "second.example.org")
        #expect(configuration.url(forDisplay: "display-1")?.host() == "home.example.org")
    }

    @Test("User scripts with an unusable shape are dropped, well-formed ones are kept")
    func userScripts() {
        let configuration = configuration([
            "injectedUserScripts": .array([
                .dictionary([
                    "source": .string("console.log(1)"),
                    "injectionTime": .string("documentStart"),
                    "mainFrameOnly": .boolean(false),
                ]),
                .dictionary(["source": .string("console.log(2)")]),
                .dictionary(["injectionTime": .string("documentEnd")]),
                .dictionary([
                    "source": .string("console.log(3)"),
                    "injectionTime": .string("whenever"),
                ]),
            ])
        ])
        let scripts = configuration.injectedUserScripts
        #expect(scripts.count == 2)
        #expect(scripts[0].injectionTime == .documentStart)
        #expect(scripts[0].mainFrameOnly == false)
        #expect(scripts[1].injectionTime == .documentEnd, "the documented default")
        #expect(scripts[1].mainFrameOnly == true, "the documented default")
    }

    @Test("The policy is built from the home URL and the allowlist together")
    func policyIsAssembled() throws {
        let configuration = configuration([
            "homeURL": .string("https://home.example.org/"),
            "allowedURLPatterns": .array([.string("sso.example.org/*")]),
        ])
        let policy = configuration.urlPolicy
        #expect(
            policy.decision(
                for: try #require(URL(string: "https://sso.example.org/x")),
                externalScheme: configuration.externalSchemePolicy
            ) == .allow
        )
        #expect(
            policy.decision(
                for: try #require(URL(string: "https://elsewhere.example.org/")),
                externalScheme: configuration.externalSchemePolicy
            ) == .blockNotAllowed
        )
    }

    @Test("Defects and refusals reach the application rather than being swallowed")
    func defectsAndRejectionsSurface() {
        let configuration = KioskConfiguration(documents: [
            ConfigurationDocument(
                origin: .managed,
                members: [
                    "homeURL": .string("https://managed.example.org/"),
                    "locked": .array([.string("homeURL")]),
                    "typo": .boolean(true),
                ]
            ),
            ConfigurationDocument(
                origin: .user,
                members: ["homeURL": .string("https://user.example.org/")]
            ),
        ])
        #expect(configuration.defects.count == 1)
        #expect(configuration.rejections.count == 1)
        #expect(configuration.rejections[0].attemptedBy == .user)
        #expect(configuration.homeURL?.host() == "managed.example.org")
    }
}
