import AppKit

/// A keyboard chord written the way a configuration file writes it, for example
/// `ctrl+alt+cmd+K`.
///
/// Parsed rather than hard-coded because the whole point of the key is that a
/// deployment can move it somewhere a visitor will not find by accident.
struct HotkeyChord: Equatable {
    let modifiers: NSEvent.ModifierFlags
    let character: String

    init?(_ text: String) {
        var modifiers: NSEvent.ModifierFlags = []
        var character: String?

        for rawPart in text.split(separator: "+") {
            let part = rawPart.trimmingCharacters(in: .whitespaces).lowercased()
            switch part {
            case "ctrl", "control": modifiers.insert(.control)
            case "alt", "opt", "option": modifiers.insert(.option)
            case "cmd", "command": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "fn", "function": modifiers.insert(.function)
            default:
                // Exactly one non-modifier part, and exactly one character in
                // it. A chord with two keys or none cannot be matched, and
                // guessing which was meant would put the escape hatch somewhere
                // nobody can find it.
                guard part.count == 1, character == nil else { return nil }
                character = part
            }
        }

        guard let character, !modifiers.isEmpty else { return nil }
        self.modifiers = modifiers
        self.character = character
    }

    func matches(_ event: NSEvent) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.control, .option, .command, .shift, .function]
        guard event.modifierFlags.intersection(relevant) == modifiers else { return false }
        return event.charactersIgnoringModifiers?.lowercased() == character
    }
}
