# Aranea browser integration

The browser integration provides managed Firefox chrome/content fragments and
a Chromium-compatible new-tab surface. Browser profiles are never edited by
the installer: assets are placed under `~/.config/aranea/browser/` and can be
copied into a profile or used by a new-tab extension when desired.

Use the canonical background, foreground, mint activity, and violet focus
roles. Do not inject browser CSS into an existing profile without a backup.
If a browser does not expose a user stylesheet or new-tab hook, fall back to
its native dark mode.
