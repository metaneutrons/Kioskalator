import SwiftUI

/// The passcode form. SwiftUI here and AppKit for the kiosk windows: this is an
/// ordinary form, and the kiosk windows need window-level control SwiftUI does
/// not give.
struct UnlockView: View {
    enum Verdict {
        case accepted
        case rejected(remaining: Int)
        case lockedOut(until: Date)
    }

    let settingsAvailable: Bool
    let verify: (String) -> Verdict
    let finish: (UnlockWindowController.Result) -> Void

    @State private var passcode = ""
    @State private var message = ""
    @State private var unlocked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(unlocked ? "Unlocked" : "Enter the exit passcode")
                .font(.headline)

            if !unlocked {
                SecureField("Passcode", text: $passcode)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                    .frame(width: 260)
            }

            if !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 260, alignment: .leading)
            }

            HStack {
                Button("Cancel") { finish(.cancelled) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if unlocked {
                    if settingsAvailable {
                        Button("Settings") { finish(.openSettings) }
                    }
                    Button("Quit") { finish(.quit) }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Unlock", action: submit)
                        .keyboardShortcut(.defaultAction)
                        .disabled(passcode.isEmpty)
                }
            }
            .frame(width: 260)
        }
        .padding(24)
    }

    private func submit() {
        switch verify(passcode) {
        case .accepted:
            unlocked = true
            message = ""
        case .rejected(let remaining):
            message = "Wrong passcode. \(remaining) attempt\(remaining == 1 ? "" : "s") left."
        case .lockedOut(let until):
            let formatted = until.formatted(date: .omitted, time: .standard)
            message = "Too many attempts. Locked until \(formatted)."
        }
        passcode = ""
    }
}
