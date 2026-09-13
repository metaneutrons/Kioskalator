import Foundation
import Testing

@testable import KioskCore

@Suite("URL patterns")
struct URLPatternTests {
    @Test(
        "A host pattern allows every path on that host",
        arguments: [
            "https://dashboard.example.org/",
            "https://dashboard.example.org/deep/path?query=1#fragment",
        ]
    )
    func hostPatternAllowsEveryPath(_ candidate: String) throws {
        let pattern = try #require(URLPattern("dashboard.example.org/*"))
        #expect(pattern.matches(try #require(URL(string: candidate))))
    }

    @Test(
        "Counter-probe: the same pattern refuses another host and another scheme",
        arguments: [
            "https://other.example.org/",
            "https://example.org/",
            "http://dashboard.example.org/",
            "https://dashboard.example.org.evil.test/",
        ]
    )
    func hostPatternRefusesEverythingElse(_ candidate: String) throws {
        let pattern = try #require(URLPattern("dashboard.example.org/*"))
        #expect(!pattern.matches(try #require(URL(string: candidate))))
    }

    @Test("A path prefix allows its subtree and nothing beside it")
    func pathPrefix() throws {
        let pattern = try #require(URLPattern("example.org/app/*"))
        #expect(pattern.matches(try #require(URL(string: "https://example.org/app/"))))
        #expect(pattern.matches(try #require(URL(string: "https://example.org/app/page"))))
        #expect(!pattern.matches(try #require(URL(string: "https://example.org/other"))))
        #expect(!pattern.matches(try #require(URL(string: "https://example.org/"))))
    }

    @Test("A path without a star has to match exactly")
    func exactPath() throws {
        let pattern = try #require(URLPattern("example.org/"))
        #expect(pattern.matches(try #require(URL(string: "https://example.org/"))))
        // A URL with an empty path is the root and has to compare equal to "/".
        #expect(pattern.matches(try #require(URL(string: "https://example.org"))))
        #expect(!pattern.matches(try #require(URL(string: "https://example.org/page"))))
    }

    @Test("A subdomain wildcard spans exactly one label")
    func subdomainWildcard() throws {
        let pattern = try #require(URLPattern("*.example.org/*"))
        #expect(pattern.matches(try #require(URL(string: "https://shop.example.org/"))))
        #expect(!pattern.matches(try #require(URL(string: "https://a.b.example.org/"))))
        #expect(!pattern.matches(try #require(URL(string: "https://example.org/"))))
        #expect(!pattern.matches(try #require(URL(string: "https://notexample.org/"))))
    }

    @Test("Without an explicit scheme only https is allowed")
    func plaintextIsRefusedByDefault() throws {
        let implicit = try #require(URLPattern("example.org/*"))
        #expect(!implicit.matches(try #require(URL(string: "http://example.org/"))))
        let explicit = try #require(URLPattern("http://example.org/*"))
        #expect(explicit.matches(try #require(URL(string: "http://example.org/"))))
        #expect(!explicit.matches(try #require(URL(string: "https://example.org/"))))
    }

    @Test("Without an explicit port only the scheme default is allowed")
    func portMustMatch() throws {
        let implicit = try #require(URLPattern("example.org/*"))
        #expect(implicit.matches(try #require(URL(string: "https://example.org:443/"))))
        #expect(!implicit.matches(try #require(URL(string: "https://example.org:8443/"))))
        let explicit = try #require(URLPattern("example.org:8443/*"))
        #expect(explicit.matches(try #require(URL(string: "https://example.org:8443/"))))
        #expect(!explicit.matches(try #require(URL(string: "https://example.org/"))))
    }

    @Test("Host matching ignores case")
    func caseInsensitiveHost() throws {
        let pattern = try #require(URLPattern("Example.ORG/*"))
        #expect(pattern.matches(try #require(URL(string: "https://EXAMPLE.org/"))))
    }

    @Test(
        "Patterns that cannot mean anything are rejected rather than guessed at",
        arguments: [
            "", "   ", "/", "://example.org", "*/", "*.org/", "ex*ample.org/",
            "example.org:0/", "example.org:99999/", "example.org:abc/",
        ]
    )
    func invalidPatternsAreRejected(_ text: String) {
        #expect(URLPattern(text) == nil, "'\(text)' should not parse")
    }
}

@Suite("Navigation policy")
struct URLPolicyTests {
    private func policy(home: String?, patterns: [String] = []) -> URLPolicy {
        URLPolicy(homeURL: home.flatMap(URL.init(string:)), patterns: patterns)
    }

    @Test("The home origin is allowed on every path without being listed")
    func homeOriginIsImplicit() throws {
        let policy = policy(home: "https://dashboard.example.org/start")
        let decision = policy.decision(
            for: try #require(URL(string: "https://dashboard.example.org/elsewhere")),
            externalScheme: .block
        )
        #expect(decision == .allow)
    }

    @Test("An empty allowlist means the home origin only")
    func emptyAllowlistIsHomeOnly() throws {
        let policy = policy(home: "https://dashboard.example.org/")
        #expect(
            policy.decision(
                for: try #require(URL(string: "https://sso.example.org/")),
                externalScheme: .block
            ) == .blockNotAllowed
        )
    }

    @Test("Counter-probe: listing the host makes the same navigation pass")
    func listedHostIsAllowed() throws {
        let policy = policy(home: "https://dashboard.example.org/", patterns: ["sso.example.org/*"])
        #expect(
            policy.decision(
                for: try #require(URL(string: "https://sso.example.org/authorize")),
                externalScheme: .block
            ) == .allow
        )
    }

    @Test("A non-web scheme follows the external-scheme policy")
    func externalSchemes() throws {
        let policy = policy(home: "https://example.org/")
        let mail = try #require(URL(string: "mailto:someone@example.org"))
        #expect(policy.decision(for: mail, externalScheme: .block) == .blockExternalScheme)
        #expect(
            policy.decision(for: mail, externalScheme: .openInDefaultApplication)
                == .openExternally
        )
    }

    @Test("A file URL is never web content, whatever the allowlist says")
    func fileURLsAreNotWebContent() throws {
        let policy = policy(home: "https://example.org/", patterns: ["*.example.org/*"])
        let file = try #require(URL(string: "file:///etc/passwd"))
        #expect(policy.decision(for: file, externalScheme: .block) == .blockExternalScheme)
    }

    @Test("A pattern that does not parse is kept for reporting, not dropped in silence")
    func invalidPatternsAreReported() {
        let policy = policy(home: "https://example.org/", patterns: ["ok.example.org/*", "*/"])
        #expect(policy.patterns.count == 1)
        #expect(policy.invalidPatterns == ["*/"])
    }

    @Test("Without a home URL nothing is implicitly allowed")
    func noHomeMeansNoImplicitOrigin() throws {
        let policy = policy(home: nil)
        #expect(
            policy.decision(
                for: try #require(URL(string: "https://example.org/")),
                externalScheme: .block
            ) == .blockNotAllowed
        )
    }
}
