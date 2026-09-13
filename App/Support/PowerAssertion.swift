import Foundation
import IOKit.pwr_mgt

/// Keeps the display awake for as long as the object lives.
///
/// Held as an object rather than taken and released around an event, so that
/// the assertion cannot outlive the reason for it: releasing it is the
/// deinitialiser's job and there is no path that forgets.
final class PowerAssertion {
    private var identifier: IOPMAssertionID = 0
    private let held: Bool

    init?(reason: String) {
        var identifier: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &identifier
        )
        guard status == kIOReturnSuccess else { return nil }
        self.identifier = identifier
        self.held = true
    }

    deinit {
        if held {
            IOPMAssertionRelease(identifier)
        }
    }
}
