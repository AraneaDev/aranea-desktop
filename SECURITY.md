# Security policy

Aranea Desktop runs parts of your desktop session: the lock screen, the
authentication (polkit) prompt, the clipboard history and the hooks Omarchy
runs on login and theme changes. Please report anything that could expose
a password, clipboard contents or other private data, bypass the lock
screen or the polkit prompt, or let another program run code through these
pieces.

## Reporting

Report privately through
[GitHub security advisories](https://github.com/AraneaDev/aranea-desktop/security/advisories/new)
rather than a public issue. Include what you did, what happened, and the
Aranea and Omarchy versions (`omarchy version`, the theme's
`theme-manifest.toml`).

You will get an acknowledgement within a week. Fixes are released as a
normal version and credited in the release notes unless you prefer not.

## Supported versions

Only the latest release is supported.
