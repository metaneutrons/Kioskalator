import Foundation

/// What the web view should do with a main-frame navigation.
public enum NavigationDecision: Sendable, Equatable {
    case allow
    /// An `http(s)` navigation outside the allowlist.
    case blockNotAllowed
    /// A non-web scheme, with `externalSchemePolicy` set to `block`.
    case blockExternalScheme
    /// A non-web scheme to be handed to the system.
    case openExternally
}

/// Decides whether a main-frame navigation may proceed.
///
/// Only main-frame navigations are policed. Subresources — images, fonts,
/// stylesheets, XHR — are not, because a CDN or a font host would otherwise
/// have to be enumerated in every allowlist, and a page that half-loads on a
/// kiosk cannot be told apart from a broken one.
public struct URLPolicy: Sendable, Equatable {
    public let homeOrigin: URLPattern?
    public let patterns: [URLPattern]
    /// Entries that could not be parsed. Kept so the application can report
    /// them: a pattern nobody noticed was rejected is an allowlist shorter than
    /// its author believes, which fails in the direction of a locked-out kiosk
    /// rather than an open one, and is still worth saying out loud.
    public let invalidPatterns: [String]

    public init(homeURL: URL?, patterns: [String]) {
        self.homeOrigin = homeURL.flatMap(URLPolicy.originPattern(for:))
        var parsed: [URLPattern] = []
        var invalid: [String] = []
        for text in patterns {
            if let pattern = URLPattern(text) {
                parsed.append(pattern)
            } else {
                invalid.append(text)
            }
        }
        self.patterns = parsed
        self.invalidPatterns = invalid
    }

    /// The home URL's own origin is always allowed, on every path. Requiring an
    /// operator to list the page they just configured as the home page is the
    /// kind of ceremony that gets answered with a `*` pattern.
    static func originPattern(for url: URL) -> URLPattern? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased(),
            !host.isEmpty
        else { return nil }
        return URLPattern(scheme: scheme, host: .exact(host), port: url.port, path: .anyPath)
    }

    public func decision(for url: URL, externalScheme: ExternalSchemePolicy) -> NavigationDecision {
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else {
            return externalScheme == .openInDefaultApplication
                ? .openExternally : .blockExternalScheme
        }
        if let homeOrigin, homeOrigin.matches(url) { return .allow }
        return patterns.contains(where: { $0.matches(url) }) ? .allow : .blockNotAllowed
    }
}
