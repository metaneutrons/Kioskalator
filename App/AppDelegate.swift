import AppKit
import KioskCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ConfigurationStore()
    private lazy var displays = DisplayCoordinator(store: store)

    private var hotkeyMonitor: Any?
    private var idleMonitor: IdleMonitor?
    private var powerAssertion: PowerAssertion?
    private var restartTimer: Timer?
    private var unlock: UnlockWindowController?
    private var settings: SettingsWindowController?
    private var isLockedDown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        MainMenu.install(
            clipboardEnabled: store.configuration.clipboardEnabled,
            quitHandler: { [weak self] in self?.requestExit() }
        )
        enterLockdown()
        displays.build()
        startHotkeyMonitor()
        startIdleMonitor()
        startPowerAssertion()
        startRestartTimer()
        NSApplication.shared.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Quitting goes through the escape hatch or through nothing. Command-Q is
    /// intercepted here rather than only by the presentation options, because
    /// the presentation options do not apply while another application is
    /// frontmost and the kiosk still has to refuse.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isLockedDown else {
            presentUnlock()
            return .terminateCancel
        }
        return .terminateNow
    }

    // MARK: Lockdown

    /// The macOS kiosk presentation options.
    ///
    /// What these genuinely do: hide the Dock and menu bar, take away the
    /// Command-Tab application switcher, the Force Quit panel and the ability to
    /// hide the application, and stop a logout or restart from the Apple menu.
    /// What they do not do: survive a power cut, a recovery boot, an
    /// administrator over SSH, or the application crashing. That boundary is in
    /// SECURITY.md, and it is not narrowed by wishing.
    private func enterLockdown() {
        NSApplication.shared.presentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableAppleMenu,
            .disableProcessSwitching,
            .disableForceQuit,
            .disableSessionTermination,
            .disableHideApplication,
            .disableMenuBarTransparency,
        ]
        isLockedDown = true
    }

    private func leaveLockdown() {
        NSApplication.shared.presentationOptions = []
        isLockedDown = false
    }

    // MARK: The escape hatch

    private func startHotkeyMonitor() {
        guard store.configuration.unlockAvailable else {
            Log.unlock.notice("no exit passcode is configured; the escape hatch is unavailable")
            return
        }
        guard let chord = HotkeyChord(store.configuration.unlockHotkey) else {
            let hotkey = store.configuration.unlockHotkey
            Log.unlock.error("unlock hotkey '\(hotkey, privacy: .public)' is unusable")
            Log.unlock.error("the escape hatch is unavailable until it is corrected")
            return
        }
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard chord.matches(event) else { return event }
            self?.presentUnlock()
            return nil
        }
    }

    private func requestExit() {
        guard isLockedDown else {
            NSApplication.shared.terminate(nil)
            return
        }
        presentUnlock()
    }

    private func presentUnlock() {
        guard store.configuration.unlockAvailable else {
            Log.unlock.notice("an exit was requested but no passcode is configured")
            return
        }
        guard unlock == nil else { return }
        let controller = UnlockWindowController(configuration: store.configuration) {
            [weak self] result in
            self?.unlock = nil
            switch result {
            case .cancelled:
                break
            case .openSettings:
                self?.presentSettings()
            case .quit:
                self?.leaveLockdown()
                NSApplication.shared.terminate(nil)
            }
        }
        unlock = controller
        controller.present()
    }

    private func presentSettings() {
        guard settings == nil else { return }
        let controller = SettingsWindowController(store: store) { [weak self] in
            self?.settings = nil
            self?.applyConfigurationChange()
        }
        settings = controller
        controller.present()
    }

    private func applyConfigurationChange() {
        store.reload()
        displays.build()
        startIdleMonitor()
        startPowerAssertion()
        startRestartTimer()
    }

    // MARK: Unattended operation

    private func startIdleMonitor() {
        idleMonitor?.stop()
        idleMonitor = nil
        guard let timeout = store.configuration.idleTimeout else { return }
        let monitor = IdleMonitor(timeout: timeout) { [weak self] in
            Log.kiosk.notice("idle timeout reached")
            self?.displays.returnToHomeAfterIdle()
        }
        monitor.start()
        idleMonitor = monitor
    }

    private func startPowerAssertion() {
        powerAssertion = nil
        guard store.configuration.preventSleep else { return }
        powerAssertion = PowerAssertion(reason: "Kioskalator is showing a kiosk page")
        if powerAssertion == nil {
            Log.kiosk.error("the display sleep assertion could not be taken")
        }
    }

    /// Relaunches the application at the configured local time.
    ///
    /// The next occurrence is recomputed against the calendar after every fire
    /// rather than a fixed 24-hour interval being added, so a daylight-saving
    /// change does not walk the restart an hour through the day.
    private func startRestartTimer() {
        restartTimer?.invalidate()
        restartTimer = nil
        guard let time = store.configuration.scheduledRestartTime,
            let next = time.nextOccurrence(after: Date())
        else { return }
        Log.kiosk.notice("the next scheduled restart is at \(next, privacy: .public)")
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.performScheduledRestart() }
        }
        RunLoop.main.add(timer, forMode: .common)
        restartTimer = timer
    }

    private func performScheduledRestart() {
        Log.kiosk.notice("performing the scheduled restart")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        {
            _, error in
            if let error {
                Log.kiosk.error(
                    "the scheduled restart could not relaunch: \(error.localizedDescription)"
                )
            }
            MainActor.assumeIsolated {
                NSApplication.shared.presentationOptions = []
                exit(0)
            }
        }
    }
}
