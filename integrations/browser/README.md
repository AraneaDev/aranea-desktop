# Aranea browser integration

The browser integration provides a palette and new-tab asset contract for
Firefox and Chromium-family browsers. Browser extensions are not a core
dependency: install the native theme assets or extension package separately,
and fall back to the browser's dark mode when the browser does not expose a
user theme API.

Use the canonical background, foreground, mint activity, and violet focus
roles. Do not inject browser CSS into an existing profile without a backup.
