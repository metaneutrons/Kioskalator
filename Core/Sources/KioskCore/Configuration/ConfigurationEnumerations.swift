import Foundation

public enum ExternalSchemePolicy: String, Sendable, CaseIterable {
    case block
    case openInDefaultApplication
}

public enum DisplayMode: String, Sendable, CaseIterable {
    /// A kiosk window on every attached display.
    case allDisplays
    /// A kiosk window on the primary display, every other display covered by an
    /// opaque window. An unlocked screen beside the kiosk defeats the lockdown.
    case primaryOnlyOthersBlanked
    /// A kiosk window on the primary display only, other displays untouched.
    case primaryOnly
}

public enum SessionPersistence: String, Sendable, CaseIterable {
    case persistent
    case ephemeral
}

public enum IdleAction: String, Sendable, CaseIterable {
    case returnHome
    case returnHomeAndClearData
}

public enum NavigationBarButton: String, Sendable, CaseIterable {
    case back
    case forward
    case reload
    case home
}
