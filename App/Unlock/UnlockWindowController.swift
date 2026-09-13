import AppKit
import KioskCore
import SwiftUI

/// The passcode dialog behind the escape hatch.
///
/// A panel of its own rather than a sheet on the kiosk window: a sheet inherits
/// the kiosk window's level and collection behaviour, and on a multi-screen
/// setup it appears over whichever window happens to be key rather than the one
/// the operator is standing at.
@MainActor
final class UnlockWindowController {
    enum Result {
        case cancelled
        case openSettings
        case quit
    }

    private let configuration: KioskConfiguration
    private var limiter: UnlockAttemptLimiter
    private var window: NSWindow?
    private let completion: (Result) -> Void

    init(configuration: KioskConfiguration, completion: @escaping (Result) -> Void) {
        self.configuration = configuration
        self.completion = completion
        self.limiter = UnlockAttemptLimiter(
            attemptLimit: configuration.unlockAttemptLimit,
            lockoutDuration: configuration.unlockLockoutDuration
        )
    }

    func present() {
        guard window == nil else { return }
        let view = UnlockView(
            settingsAvailable: configuration.settingsAccessEnabled,
            verify: { [weak self] passcode in self?.verify(passcode) ?? .rejected(remaining: 0) },
            finish: { [weak self] result in self?.finish(result) }
        )
        let hosting = NSHostingController(rootView: view)
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.titled, .closable]
        panel.title = "Kioskalator"
        panel.level = .modalPanel
        panel.isFloatingPanel = true
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        window = panel
    }

    private func verify(_ passcode: String) -> UnlockView.Verdict {
        let now = Date()
        guard let record = configuration.passcodeRecord else {
            // Cannot happen while `unlockAvailable` gates the hotkey, and is
            // still answered rather than crashed on: a dialog that appears
            // without a passcode configured must not be a way through.
            return .rejected(remaining: 0)
        }
        switch limiter.record(isCorrect: record.matches(passcode), at: now) {
        case .accepted:
            Log.unlock.notice("the exit passcode was accepted")
            return .accepted
        case .rejected(let remaining):
            Log.unlock.notice("the exit passcode was refused, \(remaining) attempts left")
            return .rejected(remaining: remaining)
        case .lockedOut(let until):
            Log.unlock.error("unlock attempts are locked out until \(until, privacy: .public)")
            return .lockedOut(until: until)
        }
    }

    private func finish(_ result: Result) {
        window?.orderOut(nil)
        window?.close()
        window = nil
        completion(result)
    }
}
