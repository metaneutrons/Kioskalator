import AppKit

/// A borderless window that fills one screen and stays above the Dock.
///
/// `canBecomeKey` has to be overridden: a borderless window refuses key status
/// by default, and without key status no text field in the page can be typed
/// into. That is the failure that makes a kiosk look like it has frozen.
final class KioskWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    convenience init(screen: NSScreen, opaqueBlack: Bool = false) {
        self.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        isReleasedWhenClosed = false
        level = .mainMenu
        collectionBehavior = [.stationary, .fullScreenNone, .ignoresCycle]
        hasShadow = false
        isMovable = false
        backgroundColor = opaqueBlack ? .black : .windowBackgroundColor
        setFrame(screen.frame, display: true)
    }

    /// Follows its screen when the arrangement or the resolution changes.
    /// Without this a resolution change leaves a kiosk window the wrong size
    /// with the desktop visible around it.
    func fill(_ screen: NSScreen) {
        setFrame(screen.frame, display: true)
    }
}
