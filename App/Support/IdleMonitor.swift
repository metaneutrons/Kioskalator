import AppKit

/// Fires once when no input has reached the application for `timeout`.
///
/// Local monitors only. A global monitor would need accessibility permission,
/// which is one more thing an unattended installation can silently lose, and
/// the kiosk is frontmost by construction anyway.
@MainActor
final class IdleMonitor {
    private let timeout: TimeInterval
    private let action: () -> Void
    private var timer: Timer?
    private var monitor: Any?

    init(timeout: TimeInterval, action: @escaping () -> Void) {
        self.timeout = timeout
        self.action = action
    }

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [
            .keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .scrollWheel, .gesture, .magnify,
        ]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.reset()
            return event
        }
        reset()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    func reset() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.action()
            }
        }
    }

    isolated deinit {
        stop()
    }
}
