# Aranea lock

`araneadev.lock` is the authentication-capable lock service. Its manifest
exposes `Service.qml` and declares the Omarchy authentication capability.

## Responsibilities

- Own the lock service lifecycle and authentication handoff.
- Compose the lock view, branding, clock, and authentication panel.
- Preserve native password and fingerprint behavior.
- Keep lock-specific artwork and paths separate from normal overlay chrome.

`LockView.qml` is the composition root. `LockBranding.qml` owns lock artwork,
`LockClock.qml` owns the clock, and `LockAuthPanel.qml` owns authentication
controls. The lock surface intentionally does not reuse the normal branded
header artwork.

## Validation

Run `tests/qml-behaviour.test.sh lock-components lock-clock-components` and
the lock signature tests.
