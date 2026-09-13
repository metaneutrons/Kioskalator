# Kioskalator

A configurable, lockable kiosk browser for macOS. Swift and WebKit, no embedded
Chromium, no runtime beyond what the system already ships.

Kioskalator puts one web page on the screen, fills every display with it, takes
the menu bar and the Dock away, and refuses to go anywhere it was not told it
may go. It keeps the parts of a browser a form actually needs — text selection,
cut, copy, paste, select-all — and drops the parts a kiosk must not have.

> **Status: pre-release.** The configuration model, the navigation policy and
> the lockdown are implemented and tested. Several keys in
> [docs/configuration.md](docs/configuration.md) are marked *planned* and say so
> in the table; they are tracked as issues and are not silently absent. There is
> no signed release yet, so the only supported route today is building from
> source.

## What it does

- **Really fullscreen.** Borderless windows at a level above the Dock, with the
  menu bar and Dock hidden through `NSApplication.presentationOptions`. One
  window per display, or one display with the others blanked, or one display
  with the others left alone — configurable, because all three are real
  deployments.
- **An embeddable, configurable URL.** The home URL comes from a configuration
  profile, a file, a remote endpoint or the settings pane, and a display can be
  given its own.
- **Ordinary browser capability where it is needed.** Copy and paste into a form
  works, because the application installs the edit menu items whose key
  equivalents WebKit actually listens for. Text selection, undo and redo work
  for the same reason.
- **A navigation allowlist.** Main-frame navigations outside the configured
  patterns are refused with a notice naming what was blocked. Subresources are
  left alone, so a page does not half-load.
- **Locking that holds.** Any configuration layer can lock a key against every
  layer below it, and managed preferences sit at the top. A locked field in the
  settings pane is greyed and names the layer holding it, instead of appearing
  to save and quietly not saving.
- **An escape hatch that fails closed.** A configurable chord opens a passcode
  dialog; the passcode is stored as a PBKDF2 record, attempts are rate limited
  and logged, and with no passcode configured there is no way out rather than a
  free one.
- **Unattended behaviour that assumes things break.** WebKit's content process
  dying triggers a reload rather than a blank page, the home URL is retried with
  backoff when the network is not up yet, and the display does not sleep.

Kioskalator sets the macOS kiosk presentation options, so while it is frontmost
the Dock and menu bar are gone and Command-Tab, the Force Quit panel, hiding the
application and logging out from the Apple menu are all unavailable. What it
cannot do is survive the power button, a recovery boot, a second account or an
administrator over SSH — and it cannot enforce anything at all once it has
crashed. [SECURITY.md](SECURITY.md) says exactly where that line runs and what
closes the rest of the gap.

## Requirements

- macOS 26 or newer
- Xcode 26.6 (Swift 6.3.3) to build

## Build from source

```bash
brew install xcodegen
git clone https://github.com/metaneutrons/Kioskalator.git
cd Kioskalator
xcodegen generate
xcodebuild build -scheme Kioskalator -destination 'platform=macOS' -derivedDataPath build
open build/Build/Products/Debug/Kioskalator.app
```

Started with no configuration, Kioskalator shows a notice saying where it looked
for one. That is deliberate: a kiosk browser that starts into a blank window
gives an installer nothing to work with.

## Quick start

Write a configuration file and restart the application:

```bash
sudo mkdir -p /Library/Application\ Support/Kioskalator
sudo tee /Library/Application\ Support/Kioskalator/configuration.json >/dev/null <<'JSON'
{
  "homeURL": "https://example.org/",
  "allowedURLPatterns": ["example.org/*"],
  "displayMode": "allDisplays",
  "idleTimeout": 300,
  "idleAction": "returnHome",
  "exitPasscode": "correct-horse-battery-staple",
  "locked": ["homeURL", "allowedURLPatterns"]
}
JSON
```

`exitPasscode` is read once, hashed and replaced in place with its PBKDF2
record, so the plaintext does not survive the first launch. Press
`ctrl+alt+cmd+K` to reach the passcode dialog.

For a fleet, the same keys go into an MDM configuration profile for the domain
`com.metaneutrons.kioskalator`, where they cannot be changed from the machine at
all. [docs/configuration.md](docs/configuration.md) has every key, the
resolution order and the locking rules.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md). Conventional Commits are binding, the
project is generated from `project.yml` with XcodeGen, and the logic that
decides anything lives in `Core/Sources/KioskCore` so it can be tested without
a
screen.

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).
