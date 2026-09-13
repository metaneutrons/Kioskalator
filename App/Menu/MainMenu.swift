import AppKit

/// Builds the application menu.
///
/// The menu bar is hidden, so this looks like dead weight and is not. WKWebView
/// routes cut, copy, paste, select-all, undo and redo through the responder
/// chain, and the key equivalents that reach it come from menu items. Without
/// this menu, Command-V does nothing in a text field and the kiosk cannot be
/// used for any form worth filling in — which is the single most common
/// complaint about home-made kiosk browsers.
@MainActor
enum MainMenu {
    static func install(clipboardEnabled: Bool, quitHandler: @escaping () -> Void) {
        let main = NSMenu()

        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let quit = NSMenuItem(
            title: "Quit Kioskalator",
            action: #selector(QuitTarget.quit(_:)),
            keyEquivalent: "q"
        )
        quit.target = QuitTarget.shared
        QuitTarget.shared.handler = quitHandler
        applicationMenu.addItem(quit)
        applicationItem.submenu = applicationMenu
        main.addItem(applicationItem)

        if clipboardEnabled {
            main.addItem(editMenuItem())
        }

        NSApplication.shared.mainMenu = main
    }

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")
        for command in MainMenu.editCommands {
            let entry = NSMenuItem(
                title: command.title,
                action: command.action,
                keyEquivalent: command.key
            )
            entry.keyEquivalentModifierMask = command.modifiers
            menu.addItem(entry)
        }
        item.submenu = menu
        return item
    }

    struct EditCommand {
        let title: String
        let action: Selector
        let key: String
        let modifiers: NSEvent.ModifierFlags
    }

    /// The commands whose key equivalents WebKit listens for. `undo:` and
    /// `redo:` have no exported selector constant, so they are named as
    /// strings; the others do and are written as `#selector` so a rename in the
    /// SDK is a compile error rather than a menu item that quietly does nothing.
    static let editCommands: [EditCommand] = [
        EditCommand(title: "Undo", action: Selector(("undo:")), key: "z", modifiers: [.command]),
        EditCommand(
            title: "Redo",
            action: Selector(("redo:")),
            key: "z",
            modifiers: [.command, .shift]
        ),
        EditCommand(
            title: "Cut",
            action: #selector(NSText.cut(_:)),
            key: "x",
            modifiers: [.command]
        ),
        EditCommand(
            title: "Copy",
            action: #selector(NSText.copy(_:)),
            key: "c",
            modifiers: [.command]
        ),
        EditCommand(
            title: "Paste",
            action: #selector(NSText.paste(_:)),
            key: "v",
            modifiers: [.command]
        ),
        EditCommand(
            title: "Paste and Match Style",
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            key: "v",
            modifiers: [.command, .option, .shift]
        ),
        EditCommand(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            key: "a",
            modifiers: [.command]
        ),
    ]
}

/// A menu item needs a target that outlives the call that built it.
@MainActor
private final class QuitTarget: NSObject {
    static let shared = QuitTarget()
    var handler: (() -> Void)?

    @objc func quit(_ sender: Any?) {
        handler?()
    }
}
