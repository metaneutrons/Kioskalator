import Foundation

/// One entry of the navigation allowlist.
///
/// Grammar, and nothing beyond it:
///
///     [<scheme>://]<host>[:<port>][/<path prefix>][*]
///
/// - The host may carry a leading `*.`, which matches exactly one label of
///   subdomain. `*.example.org` matches `shop.example.org` and matches neither
///   `example.org` nor `a.b.example.org`. One level, because a wildcard that
///   spans arbitrary depth quietly admits every host a DNS operator ever adds.
/// - A path ending in `*` is a prefix. A path without one has to match exactly.
///   A pattern with no path at all allows the whole host.
/// - Without an explicit scheme only `https` is allowed. A kiosk silently
///   downgraded to plaintext is worse than one that stops.
/// - Without an explicit port only the scheme's default port is allowed.
public struct URLPattern: Sendable, Equatable {
    public enum HostMatch: Sendable, Equatable {
        case exact(String)
        case singleLabelSubdomain(String)
    }

    public enum PathMatch: Sendable, Equatable {
        case anyPath
        case exact(String)
        case prefix(String)
    }

    public let scheme: String
    public let host: HostMatch
    public let port: Int?
    public let path: PathMatch

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let (scheme, afterScheme) = URLPattern.splitScheme(trimmed)
        guard let scheme, !afterScheme.isEmpty else { return nil }

        let (authorityText, pathText) = URLPattern.splitAuthority(afterScheme)
        guard let (host, port) = URLPattern.parseAuthority(authorityText) else { return nil }

        self.init(
            scheme: scheme,
            host: host,
            port: port,
            path: URLPattern.parsePath(pathText)
        )
    }

    /// Returns the scheme and what follows it. Without an explicit scheme only
    /// `https` is allowed: a kiosk silently downgraded to plaintext is worse
    /// than one that stops.
    private static func splitScheme(_ text: String) -> (String?, String) {
        guard let separator = text.range(of: "://") else { return ("https", text) }
        let scheme = String(text[text.startIndex..<separator.lowerBound]).lowercased()
        let remainder = String(text[separator.upperBound...])
        guard !scheme.isEmpty, scheme.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            return (nil, remainder)
        }
        return (scheme, remainder)
    }

    private static func splitAuthority(_ text: String) -> (String, String?) {
        guard let slash = text.firstIndex(of: "/") else { return (text, nil) }
        return (String(text[text.startIndex..<slash]), String(text[slash...]))
    }

    private static func parseAuthority(_ text: String) -> (HostMatch, Int?)? {
        guard !text.isEmpty else { return nil }
        var hostText = text
        var port: Int?
        if let colon = hostText.lastIndex(of: ":") {
            let portText = hostText[hostText.index(after: colon)...]
            guard let parsed = Int(portText), (1...65535).contains(parsed) else { return nil }
            port = parsed
            hostText = String(hostText[hostText.startIndex..<colon])
        }
        hostText = hostText.lowercased()
        guard !hostText.isEmpty else { return nil }

        if let suffix = hostText.strippingPrefix("*.") {
            guard suffix.contains("."), !suffix.contains("*") else { return nil }
            return (.singleLabelSubdomain(suffix), port)
        }
        guard !hostText.contains("*") else { return nil }
        return (.exact(hostText), port)
    }

    private static func parsePath(_ text: String?) -> PathMatch {
        guard let text else { return .anyPath }
        if text.hasSuffix("*") { return .prefix(String(text.dropLast())) }
        return .exact(text)
    }

    public init(scheme: String, host: HostMatch, port: Int?, path: PathMatch) {
        self.scheme = scheme
        self.host = host
        self.port = port
        self.path = path
    }

    public func matches(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == scheme else { return false }
        guard let urlHost = url.host()?.lowercased(), !urlHost.isEmpty else { return false }

        switch host {
        case .exact(let expected):
            guard urlHost == expected else { return false }
        case .singleLabelSubdomain(let parent):
            guard let label = urlHost.strippingSuffix("." + parent),
                !label.isEmpty, !label.contains(".")
            else { return false }
        }

        let effectivePort = url.port ?? URLPattern.defaultPort(forScheme: scheme)
        guard effectivePort == (port ?? URLPattern.defaultPort(forScheme: scheme)) else {
            return false
        }

        // An empty path in a URL is the root, and the two have to compare equal
        // or `https://example.org` would not match the pattern `example.org/`.
        let urlPath = url.path().isEmpty ? "/" : url.path()
        switch path {
        case .anyPath: return true
        case .exact(let expected): return urlPath == expected
        case .prefix(let expected): return urlPath.hasPrefix(expected)
        }
    }

    static func defaultPort(forScheme scheme: String) -> Int? {
        switch scheme {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}

extension String {
    func strippingPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }

    func strippingSuffix(_ suffix: String) -> String? {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : nil
    }
}
