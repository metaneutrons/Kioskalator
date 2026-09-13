# Configuration

Kioskalator reads every setting through one resolver. This document is the
reference for what can be set, where it can be set and what an administrator can
take away from the person on site.

The preference domain is `com.metaneutrons.kioskalator`.

## The four layers

A setting can arrive from four places. They are consulted in this order, and the
first layer that supplies a value wins:

| Rank | Layer | Where it lives | Who writes it |
| --- | --- | --- | --- |
| 1 | Managed preferences | A configuration profile pushed by MDM, read through `CFPreferencesAppValueIsForced` | Jamf, Intune, Mosyle, or a profile installed by hand |
| 2 | Remote configuration | JSON fetched from `remoteConfigurationURL`, signature checked | Whoever operates the fleet endpoint |
| 3 | Local file | `/Library/Application Support/Kioskalator/configuration.json` | An administrator with root, Ansible, a provisioning script |
| 4 | In-app settings | The user defaults of the application, read by the resolver; the settings pane that writes them is [#3](https://github.com/metaneutrons/Kioskalator/issues/3) | The person on site |

Below all four sits the built-in default. A key with no value anywhere resolves
to its default, and the resolver reports the origin as `default` so the settings
pane can say so.

## Locking

**Every key is lockable, and any layer may lock a key.** A lock applies
downward: once layer *n* locks a key, every layer below *n* is refused for that
key. Managed preferences sit at rank 1, so what MDM locks cannot be changed by
anything else, which is the whole point of pushing a profile.

A lock is declared in the same document as the value, under a sibling key:

```json
{
  "homeURL": "https://dashboard.example.org/",
  "allowedURLPatterns": ["dashboard.example.org/*", "sso.example.org/*"],
  "locked": ["homeURL", "allowedURLPatterns", "exitPasscode"]
}
```

Three properties of that design, each of which exists because the obvious
alternative fails in practice:

- **A refused write is refused visibly.** A lower layer that tries to set a
  locked key gets an error naming the layer that holds the lock; it is not
  discarded in silence. A setting that appears to save and then does not is the
  single most expensive kind of support call on an unattended machine.
- **A lock can be declared without a value.** `"locked": ["homeURL"]` with no
  `homeURL` freezes whatever the layers below already resolved to. That lets a
  profile pin a per-machine value it does not itself know.
- **The settings pane shows the origin of every key** and which layer holds its
  lock. An administrator on site can then see why a value is what it is, instead
  of concluding the application is broken. The pane is **read-only today**:
  layer 4 exists in the resolver and in `ConfigurationStore.write(_:for:)`, and
  the editing surface on top of it is
  [#3](https://github.com/metaneutrons/Kioskalator/issues/3).

A key can also be locked *empty*, which is how a capability is taken away
rather than configured: `"allowFileUploads": false` plus a lock on it means no
layer below, and no person at the keyboard, can turn uploads back on.

## Keys

Status column: **live** is implemented and tested; **planned** is specified here
and tracked as the linked issue, and the resolver rejects it as an unknown key
until it lands. Nothing in this table is claimed to work before it does, and a
planned key in a configuration document is reported as a defect rather than
ignored.

### Content

| Key | Type | Default | Status | What it does |
| --- | --- | --- | --- | --- |
| `homeURL` | URL | none | live | The page the kiosk shows. Without it Kioskalator starts into the configuration notice rather than a blank window. |
| `userAgent` | string | system | live | Replaces the WKWebView user agent, so the served site can detect the kiosk. |
| `injectedStyleSheets` | [string] | `[]` | live | CSS injected at document start, one entry per stylesheet. |
| `injectedUserScripts` | [object] | `[]` | live | JavaScript injected at `documentStart` or `documentEnd`. Each entry is `{source, injectionTime, mainFrameOnly}`. |
| `nativeBridgeEnabled` | bool | `false` | [planned](https://github.com/metaneutrons/Kioskalator/issues/5) | Exposes a `WKScriptMessageHandler` to the page. |
| `nativeBridgeAllowedOrigins` | [string] | `[]` | [planned](https://github.com/metaneutrons/Kioskalator/issues/5) | Origins the bridge answers. An empty list with the bridge on is a configuration error, not an open door. |

`injectedUserScripts` is code execution inside the kiosk's browsing context. It
is a key an MDM profile should normally lock, so that a passcode holder on site
cannot add a script; the settings pane will not offer it while it is locked.

### Navigation

| Key | Type | Default | Status | What it does |
| --- | --- | --- | --- | --- |
| `allowedURLPatterns` | [string] | `[]` | live | Main-frame navigations permitted beyond the home URL's own origin. Empty means the home origin only. |
| `allowPopups` | bool | `false` | live | Whether `window.open` and `target="_blank"` may open. When off, the navigation is redirected into the same view if it is allowed, and refused otherwise. |
| `externalSchemePolicy` | enum | `block` | live | What happens to `mailto:`, `tel:` and other non-http schemes. `block` or `openInDefaultApplication`. |
| `allowDownloads` | bool | `false` | live | Downloads are refused by default; a download on a kiosk is a file on a machine nobody administers. |
| `allowFileUploads` | bool | `false` | live | Whether a file input may open a picker at all. |
| `fileUploadDirectory` | path | none | [planned](https://github.com/metaneutrons/Kioskalator/issues/10) | Restricts the picker to one directory. Without it an upload picker is a file browser, and a file browser is an escape route. |

**Pattern syntax.** A pattern is `host/path-prefix`, where the host may carry a
leading `*.` for one level of subdomain wildcard and the path may end in `*`.
`dashboard.example.org/*` allows every path on that host; `example.org/app/*`
allows one subtree; `*.example.org/` allows the root of any direct subdomain.
A pattern with a scheme (`https://…`) restricts the scheme too; without one,
`https` is required and `http` is refused, because a kiosk silently downgraded
to plaintext is worse than one that stops.

**Only main-frame navigations are policed.** Subresources — images, fonts,
stylesheets, XHR — are not, because a CDN or a font host would otherwise have to
be enumerated in the allowlist, and a page that half-loads on a kiosk is
indistinguishable from a broken one. If a deployment needs subresources
restricted too, that is a content blocker rule set, and it is a separate key
rather than an overload of this one.

### Displays

| Key | Type | Default | Status | What it does |
| --- | --- | --- | --- | --- |
| `displayMode` | enum | `allDisplays` | live | `allDisplays` puts a kiosk window on every screen; `primaryOnlyOthersBlanked` covers the others with a black window; `primaryOnly` leaves them alone. |
| `displayURLOverrides` | object | `{}` | live | Maps a display identifier to its own URL. Keys are the display's persistent identifier, printable from the settings pane. |

`primaryOnly` leaves the desktop visible and clickable on every other screen,
which defeats the lockdown on a multi-head machine. It exists because a single
kiosk pane beside an operator's working screen is a real deployment, not because
it is a sensible default.

### Session

| Key | Type | Default | Status | What it does |
| --- | --- | --- | --- | --- |
| `sessionPersistence` | enum | `persistent` | live | `persistent` keeps cookies and local storage across restarts, so a logged-in dashboard stays logged in. `ephemeral` keeps nothing. |
| `idleTimeout` | seconds | `0` | live | Idle time after which the kiosk acts. `0` switches it off. |
| `idleAction` | enum | `returnHome` | live | `returnHome`, or `returnHomeAndClearData` for a public terminal where the next person must not inherit a session. |

### Unattended operation

| Key | Type | Default | Status | What it does |
| --- | --- | --- | --- | --- |
| `reloadOnContentProcessTermination` | bool | `true` | live | WebKit's content process dying is otherwise a silent blank page that looks exactly like a dead machine. |
| `startupRetryEnabled` | bool | `true` | live | Retry the home URL with growing delay when it is unreachable. A kiosk usually starts before the network is up. |
| `startupRetryMaximumDelay` | seconds | `60` | live | Ceiling for that backoff. |
| `preventSleep` | bool | `true` | live | Holds a power assertion so the display does not sleep under the kiosk. |
| `scheduledReloadInterval` | seconds | `0` | live | Periodic reload, against single-page applications that leak. `0` is off. |
| `scheduledRestartTime` | `HH:mm` | none | live | Relaunch the application at a fixed local time. |
| `displaySchedule` | [object] | `[]` | [planned](https://github.com/metaneutrons/Kioskalator/issues/9) | Blank and wake the screen on a weekday schedule. |

### Administration

| Key | Type | Default | Status | What it does |
| --- | --- | --- | --- | --- |
| `exitPasscode` | string | none | live | Write-only. What is stored is a PBKDF2-HMAC-SHA256 record with a random salt, never the passcode. Reading the key back yields the record, not the secret. |
| `unlockEnabled` | bool | `true` | live | Whether the escape hatch exists at all. Locked to `false` by a profile, only removing that profile ends the kiosk. |
| `unlockHotkey` | string | `ctrl+alt+cmd+K` | live | The chord that opens the passcode dialog. |
| `unlockAttemptLimit` | int | `5` | live | Failed attempts before a lockout. |
| `unlockLockoutSeconds` | seconds | `300` | live | How long that lockout lasts. Attempts are logged either way. |
| `settingsAccessEnabled` | bool | `true` | live | Whether a correct passcode opens the settings pane, or only offers to quit. |

Without an `exitPasscode` the escape hatch is unavailable rather than open. A
kiosk that can be left by pressing a chord and confirming nothing is not a
kiosk, so the absent-passcode case fails closed.

### Chrome

| Key | Type | Default | Status | What it does |
| --- | --- | --- | --- | --- |
| `showNavigationBar` | bool | `false` | live | A slim bar above the content. Off by default; the content is the product. |
| `navigationBarButtons` | [enum] | `[back, reload, home]` | live | Which of `back`, `forward`, `reload`, `home` the bar carries. |
| `clipboardEnabled` | bool | `true` | live | Cut, copy, paste and select-all. Switching it off removes the menu items, which is the only thing that actually disables the key equivalents. |

The error screen is deliberately not configurable away. A kiosk showing a white
page cannot be told apart from a kiosk whose machine has died, and the person
who has to decide that is usually on the phone.

### Network and trust

| Key | Type | Default | Status | What it does |
| --- | --- | --- | --- | --- |
| `clientCertificateIdentity` | string | none | [planned](https://github.com/metaneutrons/Kioskalator/issues/6) | Keychain label of the identity used for mTLS. |
| `pinnedCertificateSHA256` | [string] | `[]` | [planned](https://github.com/metaneutrons/Kioskalator/issues/6) | Accept a private CA or a self-signed certificate by fingerprint. Deliberately not a switch that accepts everything. |
| `basicAuthCredentialReference` | object | `{}` | [planned](https://github.com/metaneutrons/Kioskalator/issues/6) | Keychain reference per host. The password goes in the Keychain, never in the configuration document. |
| `proxyConfiguration` | object | none | [planned](https://github.com/metaneutrons/Kioskalator/issues/6) | Per-application proxy, rather than a system-wide one. |

### Remote management

| Key | Type | Default | Status | What it does |
| --- | --- | --- | --- | --- |
| `controlAPIEnabled` | bool | `false` | [planned](https://github.com/metaneutrons/Kioskalator/issues/7) | A loopback-bound HTTP API: status, reload, navigate, reset, reconfigure. |
| `controlAPIPort` | int | `8377` | [planned](https://github.com/metaneutrons/Kioskalator/issues/7) | Its port. Bound to `127.0.0.1` only, never to a routable address. |
| `controlAPITokenReference` | string | none | [planned](https://github.com/metaneutrons/Kioskalator/issues/7) | Keychain reference for the bearer token. Enabling the API without a token is a configuration error. |
| `mqttEnabled` | bool | `false` | [planned](https://github.com/metaneutrons/Kioskalator/issues/8) | Publish health and subscribe to commands. |
| `mqttBrokerURL` | URL | none | [planned](https://github.com/metaneutrons/Kioskalator/issues/8) | Broker endpoint. |
| `mqttBaseTopic` | string | `kioskalator` | [planned](https://github.com/metaneutrons/Kioskalator/issues/8) | Topic prefix; the kiosk identifier is appended. |
| `mqttCredentialReference` | string | none | [planned](https://github.com/metaneutrons/Kioskalator/issues/8) | Keychain reference for broker credentials. |

### Remote configuration

| Key | Type | Default | Status | What it does |
| --- | --- | --- | --- | --- |
| `remoteConfigurationURL` | URL | none | [planned](https://github.com/metaneutrons/Kioskalator/issues/4) | Where layer 2 is fetched from. |
| `remoteConfigurationPublicKey` | string | none | [planned](https://github.com/metaneutrons/Kioskalator/issues/4) | Ed25519 public key, base64. A remote configuration without a valid signature is discarded and the previous one is kept. |
| `remoteConfigurationRefreshInterval` | seconds | `900` | [planned](https://github.com/metaneutrons/Kioskalator/issues/4) | How often it is refetched. |

`remoteConfigurationURL` without `remoteConfigurationPublicKey` is refused at
load. An unsigned endpoint that can repoint the kiosk is a remote code path in
everything but name, and making it optional means it would be optional in
practice.

## Not configuration, and not implemented either

Three things the deployment model assumes and the code does not have yet. They
are listed here because reading only the key table would suggest they exist.

- **Automatic updates.** Sparkle is the chosen channel and none of it is built:
  no framework, no EdDSA key, no appcast.
  [#11](https://github.com/metaneutrons/Kioskalator/issues/11). An
  auto-updating kiosk also needs a maintenance window, which will be a key here
  once there is something to gate.
- **A watchdog.** The kiosk presentation options hold while the application is
  running and frontmost. Nothing currently brings it back after a crash.
  [#12](https://github.com/metaneutrons/Kioskalator/issues/12).
- **Touchscreen focus handling.** A focused field does not scroll clear of the
  system accessibility keyboard, and that keyboard is not reachable from a
  locked-down kiosk with no physical keyboard attached.
  [#13](https://github.com/metaneutrons/Kioskalator/issues/13).

## What a kiosk cannot do

Stated here rather than discovered later. Kioskalator hides the menu bar and the
Dock, intercepts the quit, hide and window-switching key equivalents and can
occupy every screen. It cannot stop **Force Quit**, the power button, a recovery
boot, or a second user account. Those are enforced by the operating system, and
if the deployment needs them, the answers are an MDM restriction payload, a
firmware password and a locked enclosure. A watchdog that relaunches the
application after a Force Quit is tracked separately; it narrows the window, it
does not close it.
