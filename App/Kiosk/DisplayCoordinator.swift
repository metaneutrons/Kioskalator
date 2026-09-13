import AppKit
import KioskCore

/// Owns one window per screen and keeps that set right as screens come and go.
///
/// Rebuilding on every screen change rather than patching the existing set: a
/// display that is unplugged, replugged at a different resolution and arranged
/// on the other side is three separate notifications, and reconciling them
/// incrementally is how a kiosk ends up with a window on a screen that no
/// longer exists.
@MainActor
final class DisplayCoordinator {
    private let store: ConfigurationStore
    private var windows: [NSWindow] = []
    private var controllers: [KioskViewController] = []

    init(store: ConfigurationStore) {
        self.store = store
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    var kioskControllers: [KioskViewController] { controllers }

    func build() {
        teardown()
        let configuration = store.configuration
        let screens = NSScreen.screens
        guard let primary = screens.first else {
            Log.kiosk.error("no screen is attached")
            return
        }

        switch configuration.displayMode {
        case .allDisplays:
            for screen in screens {
                addKioskWindow(on: screen, configuration: configuration)
            }
        case .primaryOnlyOthersBlanked:
            addKioskWindow(on: primary, configuration: configuration)
            for screen in screens.dropFirst() {
                addBlankingWindow(on: screen)
            }
        case .primaryOnly:
            addKioskWindow(on: primary, configuration: configuration)
        }

        windows.first?.makeKeyAndOrderFront(nil)
    }

    func reloadHome() {
        for controller in controllers {
            controller.loadHome()
        }
    }

    func returnToHomeAfterIdle() {
        for controller in controllers {
            controller.returnToHomeAfterIdle()
        }
    }

    func teardown() {
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        controllers.removeAll()
    }

    private func addKioskWindow(on screen: NSScreen, configuration: KioskConfiguration) {
        let identifier = DisplayCoordinator.identifier(for: screen)
        let controller = KioskViewController(
            configuration: configuration,
            url: configuration.url(forDisplay: identifier)
        )
        let window = KioskWindow(screen: screen)
        window.contentViewController = controller
        window.orderFrontRegardless()
        windows.append(window)
        controllers.append(controller)
    }

    private func addBlankingWindow(on screen: NSScreen) {
        let window = KioskWindow(screen: screen, opaqueBlack: true)
        window.contentView = NSView()
        window.orderFrontRegardless()
        windows.append(window)
    }

    /// A stable name for a screen, so `displayURLOverrides` can address one.
    ///
    /// `NSScreen.localizedName` alone is not enough: two identical monitors
    /// report the same name, and the override would then apply to whichever the
    /// enumeration happened to produce first. The `CGDirectDisplayID` makes it
    /// unique, and the name is kept because it is the half an administrator can
    /// recognise.
    static func identifier(for screen: NSScreen) -> String {
        let number =
            screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber
        guard let number else { return screen.localizedName }
        return "\(screen.localizedName)#\(number.uint32Value)"
    }

    @objc private func screensChanged() {
        Log.kiosk.notice("the screen arrangement changed; rebuilding the kiosk windows")
        build()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
