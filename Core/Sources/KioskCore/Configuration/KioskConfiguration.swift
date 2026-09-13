import Foundation

/// A user script as the configuration declares it.
public struct InjectedUserScript: Sendable, Equatable {
    public enum InjectionTime: String, Sendable, CaseIterable {
        case documentStart
        case documentEnd
    }

    public let source: String
    public let injectionTime: InjectionTime
    public let mainFrameOnly: Bool

    public init(source: String, injectionTime: InjectionTime, mainFrameOnly: Bool) {
        self.source = source
        self.injectionTime = injectionTime
        self.mainFrameOnly = mainFrameOnly
    }

    init?(_ value: ConfigurationValue) {
        guard let members = value.dictionaryValue,
            let source = members["source"]?.stringValue
        else { return nil }
        let time = members["injectionTime"]?.stringValue ?? InjectionTime.documentEnd.rawValue
        guard let injectionTime = InjectionTime(rawValue: time) else { return nil }
        self.init(
            source: source,
            injectionTime: injectionTime,
            mainFrameOnly: members["mainFrameOnly"]?.booleanValue ?? true
        )
    }
}

/// Typed access to a resolved configuration.
///
/// Every accessor falls back to the key's own default rather than to a literal
/// written here. One default per key, in `ConfigurationKey.defaultValue`, is
/// one place to be wrong instead of two that can disagree.
public struct KioskConfiguration: Sendable {
    public let resolved: ResolvedConfiguration

    public init(_ resolved: ResolvedConfiguration) {
        self.resolved = resolved
    }

    public init(documents: [ConfigurationDocument]) {
        self.init(ConfigurationResolver.resolve(documents))
    }

    // MARK: Raw access

    public func value(_ key: ConfigurationKey) -> ConfigurationValue? { resolved[key] }

    public func setting(_ key: ConfigurationKey) -> ResolvedSetting? {
        resolved.setting(for: key)
    }

    public var rejections: [ConfigurationRejection] { resolved.rejections }
    public var defects: [ConfigurationDefect] { resolved.defects }

    private func boolean(_ key: ConfigurationKey) -> Bool {
        resolved[key]?.booleanValue ?? key.defaultValue?.booleanValue ?? false
    }

    private func integer(_ key: ConfigurationKey) -> Int {
        resolved[key]?.integerValue ?? key.defaultValue?.integerValue ?? 0
    }

    private func string(_ key: ConfigurationKey) -> String? {
        resolved[key]?.stringValue ?? key.defaultValue?.stringValue
    }

    private func strings(_ key: ConfigurationKey) -> [String] {
        resolved[key]?.stringArrayValue ?? key.defaultValue?.stringArrayValue ?? []
    }

    private func enumeration<T: RawRepresentable>(_ key: ConfigurationKey, _ type: T.Type) -> T?
    where T.RawValue == String {
        string(key).flatMap(T.init(rawValue:))
    }

    // MARK: Content

    /// The home URL, or `nil` when none is configured or the configured one is
    /// not a usable absolute URL. Kioskalator then shows the configuration
    /// notice; it does not start into a blank window.
    public var homeURL: URL? {
        guard let raw = string(.homeURL), let url = URL(string: raw), url.scheme != nil else {
            return nil
        }
        return url
    }

    public var userAgent: String? { string(.userAgent) }

    public var injectedStyleSheets: [String] { strings(.injectedStyleSheets) }

    public var injectedUserScripts: [InjectedUserScript] {
        (resolved[.injectedUserScripts]?.arrayValue ?? []).compactMap(InjectedUserScript.init)
    }

    // MARK: Navigation

    public var allowedURLPatterns: [String] { strings(.allowedURLPatterns) }
    public var allowPopups: Bool { boolean(.allowPopups) }
    public var allowDownloads: Bool { boolean(.allowDownloads) }
    public var allowFileUploads: Bool { boolean(.allowFileUploads) }

    public var externalSchemePolicy: ExternalSchemePolicy {
        enumeration(.externalSchemePolicy, ExternalSchemePolicy.self) ?? .block
    }

    /// The policy the web view enforces, built from the home URL and the
    /// allowlist. An empty allowlist means the home origin only.
    public var urlPolicy: URLPolicy {
        URLPolicy(homeURL: homeURL, patterns: allowedURLPatterns)
    }

    // MARK: Displays

    public var displayMode: DisplayMode {
        enumeration(.displayMode, DisplayMode.self) ?? .allDisplays
    }

    public func url(forDisplay identifier: String) -> URL? {
        guard let overrides = resolved[.displayURLOverrides]?.dictionaryValue,
            let raw = overrides[identifier]?.stringValue,
            let url = URL(string: raw), url.scheme != nil
        else { return homeURL }
        return url
    }

    // MARK: Session

    public var sessionPersistence: SessionPersistence {
        enumeration(.sessionPersistence, SessionPersistence.self) ?? .persistent
    }

    public var idleAction: IdleAction {
        enumeration(.idleAction, IdleAction.self) ?? .returnHome
    }

    /// `nil` when idle handling is off. Negative and zero both mean off; a
    /// negative timeout otherwise becomes a timer that fires immediately and
    /// forever.
    public var idleTimeout: TimeInterval? {
        let seconds = integer(.idleTimeout)
        return seconds > 0 ? TimeInterval(seconds) : nil
    }

    // MARK: Unattended operation

    public var reloadsOnContentProcessTermination: Bool {
        boolean(.reloadOnContentProcessTermination)
    }

    public var startupRetryEnabled: Bool { boolean(.startupRetryEnabled) }

    public var startupRetryMaximumDelay: TimeInterval {
        TimeInterval(max(1, integer(.startupRetryMaximumDelay)))
    }

    public var preventSleep: Bool { boolean(.preventSleep) }

    public var scheduledReloadInterval: TimeInterval? {
        let seconds = integer(.scheduledReloadInterval)
        return seconds > 0 ? TimeInterval(seconds) : nil
    }

    public var scheduledRestartTime: TimeOfDay? {
        string(.scheduledRestartTime).flatMap(TimeOfDay.init(text:))
    }

    // MARK: Administration

    public var passcodeRecord: PasscodeRecord? {
        string(.exitPasscode).flatMap(PasscodeRecord.init(encoded:))
    }

    /// The escape hatch exists only when it is switched on **and** a passcode is
    /// configured. A chord that opens a dialog anyone can confirm is not a lock.
    public var unlockAvailable: Bool { boolean(.unlockEnabled) && passcodeRecord != nil }

    public var unlockHotkey: String {
        string(.unlockHotkey) ?? "ctrl+alt+cmd+K"
    }

    public var unlockAttemptLimit: Int { max(1, integer(.unlockAttemptLimit)) }

    public var unlockLockoutDuration: TimeInterval {
        TimeInterval(max(0, integer(.unlockLockoutSeconds)))
    }

    public var settingsAccessEnabled: Bool { boolean(.settingsAccessEnabled) }

    // MARK: Chrome

    public var showNavigationBar: Bool { boolean(.showNavigationBar) }
    public var clipboardEnabled: Bool { boolean(.clipboardEnabled) }

    public var navigationBarButtons: [NavigationBarButton] {
        strings(.navigationBarButtons).compactMap(NavigationBarButton.init(rawValue:))
    }
}
