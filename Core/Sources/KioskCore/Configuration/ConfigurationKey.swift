import Foundation

/// The kind a key's value has to have. The resolver checks it, so a mistyped
/// key is reported with the layer it came from rather than surfacing later as
/// behaviour nobody configured.
public enum ConfigurationKind: Sendable, Equatable {
    case boolean
    case integer
    case string
    case stringArray
    case dictionary
    case objectArray
}

/// Every setting Kioskalator understands.
///
/// The set is closed on purpose. A key that is not in here is reported as
/// unknown with the layer that supplied it, because a typo in an MDM profile
/// otherwise looks exactly like a setting that had no effect.
public enum ConfigurationKey: String, Sendable, CaseIterable, Comparable {
    // Content
    case homeURL
    case userAgent
    case injectedStyleSheets
    case injectedUserScripts

    // Navigation
    case allowedURLPatterns
    case allowPopups
    case externalSchemePolicy
    case allowDownloads
    case allowFileUploads

    // Displays
    case displayMode
    case displayURLOverrides

    // Session
    case sessionPersistence
    case idleTimeout
    case idleAction

    // Unattended operation
    case reloadOnContentProcessTermination
    case startupRetryEnabled
    case startupRetryMaximumDelay
    case preventSleep
    case scheduledReloadInterval
    case scheduledRestartTime

    // Administration
    case exitPasscode
    case unlockEnabled
    case unlockHotkey
    case unlockAttemptLimit
    case unlockLockoutSeconds
    case settingsAccessEnabled

    // Chrome
    case showNavigationBar
    case navigationBarButtons
    case clipboardEnabled

    public static func < (lhs: ConfigurationKey, rhs: ConfigurationKey) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension ConfigurationKey {
    /// The reserved member name a document uses to declare its locks. It is not
    /// a key and is never resolved as one.
    public static let lockDeclarationName = "locked"

    public var kind: ConfigurationKind {
        switch self {
        case .homeURL, .userAgent, .externalSchemePolicy, .displayMode,
            .sessionPersistence, .idleAction, .scheduledRestartTime,
            .exitPasscode, .unlockHotkey:
            return .string
        case .allowPopups, .allowDownloads, .allowFileUploads, .preventSleep,
            .reloadOnContentProcessTermination, .startupRetryEnabled,
            .unlockEnabled, .settingsAccessEnabled, .showNavigationBar,
            .clipboardEnabled:
            return .boolean
        case .idleTimeout, .startupRetryMaximumDelay, .scheduledReloadInterval,
            .unlockAttemptLimit, .unlockLockoutSeconds:
            return .integer
        case .injectedStyleSheets, .allowedURLPatterns, .navigationBarButtons:
            return .stringArray
        case .displayURLOverrides:
            return .dictionary
        case .injectedUserScripts:
            return .objectArray
        }
    }

    /// The value in force when no layer supplies one.
    ///
    /// `nil` means the key genuinely has no default and the feature it governs
    /// is unavailable until it is configured. `exitPasscode` is the important
    /// one: with no passcode the escape hatch does not exist, rather than
    /// standing open.
    public var defaultValue: ConfigurationValue? {
        switch self {
        case .homeURL, .userAgent, .scheduledRestartTime, .exitPasscode:
            return nil
        case .injectedStyleSheets, .injectedUserScripts, .allowedURLPatterns:
            return .array([])
        case .displayURLOverrides:
            return .dictionary([:])
        case .allowPopups, .allowDownloads, .allowFileUploads, .showNavigationBar:
            return .boolean(false)
        case .reloadOnContentProcessTermination, .startupRetryEnabled, .preventSleep,
            .unlockEnabled, .settingsAccessEnabled, .clipboardEnabled:
            return .boolean(true)
        case .externalSchemePolicy:
            return .string(ExternalSchemePolicy.block.rawValue)
        case .displayMode:
            return .string(DisplayMode.allDisplays.rawValue)
        case .sessionPersistence:
            return .string(SessionPersistence.persistent.rawValue)
        case .idleAction:
            return .string(IdleAction.returnHome.rawValue)
        case .idleTimeout, .scheduledReloadInterval:
            return .integer(0)
        case .startupRetryMaximumDelay:
            return .integer(60)
        case .unlockAttemptLimit:
            return .integer(5)
        case .unlockLockoutSeconds:
            return .integer(300)
        case .unlockHotkey:
            return .string("ctrl+alt+cmd+K")
        case .navigationBarButtons:
            return .array([.string("back"), .string("reload"), .string("home")])
        }
    }

    /// Whether the settings pane may ever offer this key. `exitPasscode` is
    /// write-only there, and the resolved value is a hash record rather than
    /// the secret, so reading it back shows nothing useful.
    public var isSecret: Bool { self == .exitPasscode }
}
