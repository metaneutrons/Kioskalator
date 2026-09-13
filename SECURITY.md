# Security policy

## Reporting a vulnerability

Report privately through GitHub's private vulnerability reporting:
<https://github.com/metaneutrons/Kioskalator/security/advisories/new>.
Do not open a public issue for a vulnerability.

You get a first response within 7 days. If a report is confirmed, the fix ships
in the next release and the advisory is published with it.

## What counts as a vulnerability here

Kioskalator is a lockdown product, so its threat model is the person standing in
front of the screen and the network the kiosk sits on. These are in scope:

- A way to leave the kiosk, reach the Finder, another application or a shell
  without the exit passcode.
- A navigation that escapes the configured allowlist, including through a
  redirect, a popup, a download, a file picker or a custom URL scheme.
- A way to read or change a setting an administrator has locked, or to learn the
  exit passcode from disk, memory or a log.
- A way for the displayed page to reach native capability it was not granted,
  through the JavaScript bridge or an injected script.
- A remote configuration or update that is accepted without its trust check.

These are **out of scope**, and the README says so plainly rather than implying
otherwise:

- Anything that needs physical or administrative access to the machine: the
  power button, a recovery boot, single-user mode, a second account, an
  administrator over SSH. No application can prevent those. A kiosk that must
  survive them needs MDM restrictions and a locked enclosure, and Kioskalator
  documents that rather than pretending to replace it.

  Force Quit is a partial case worth stating exactly. Kioskalator sets the macOS
  kiosk presentation options, which include `disableForceQuit`, so the Force
  Quit panel does not open while the application is frontmost. That holds
  because the application is not sandboxed. It does **not** hold if the
  application crashes, is killed from a terminal, or loses frontmost status to
  something that gets in front of it. A report that the Force Quit panel opens
  while Kioskalator is frontmost and locked down is in scope; one that it opens
  after the application has already died is not.
- Vulnerabilities in WebKit itself. Report those to Apple; Kioskalator inherits
  the system WebKit and cannot patch it.
- The content of the page you configured. Kioskalator does not sandbox a site
  against its own operator.

## Supported versions

The most recent release. There is no long-term support branch.
