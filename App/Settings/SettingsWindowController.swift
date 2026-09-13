import AppKit
import KioskCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let store: ConfigurationStore
    private var window: NSWindow?
    private let completion: () -> Void

    init(store: ConfigurationStore, completion: @escaping () -> Void) {
        self.store = store
        self.completion = completion
    }

    func present() {
        guard window == nil else { return }
        let hosting = NSHostingController(
            rootView: SettingsView(store: store, close: { [weak self] in self?.close() })
        )
        let panel = NSWindow(contentViewController: hosting)
        panel.title = "Kioskalator Settings"
        panel.styleMask = [.titled, .closable, .resizable]
        panel.level = .modalPanel
        panel.setContentSize(NSSize(width: 720, height: 520))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        window = panel
    }

    private func close() {
        window?.orderOut(nil)
        window?.close()
        window = nil
        completion()
    }
}
