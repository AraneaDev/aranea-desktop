# Troubleshooting

## Start with the doctor

```bash
scripts/aranea-doctor
scripts/aranea-doctor --json
scripts/aranea-doctor --fix
```

The doctor checks the active theme, hooks, manifest, icons, ownership, shell
plugins, runtime logs, integrations, notifications, and optional tooling.
`repair` means a check needs attention; `skipped` usually means an optional
dependency is not installed.

## Aranea is not active

```bash
omarchy theme current
omarchy theme set aranea
scripts/aranea-doctor --fix
```

Switching themes intentionally hands host-owned surfaces back to Omarchy. Set
Aranea active again if you want its shell plugins and integrations restored.

## Hooks or plugins are stale

Run:

```bash
scripts/aranea-doctor --fix
omarchy restart shell
```

The repair path reinstalls the theme-set and post-boot hooks and reconciles
deployed plugins.

## The spider mark is missing

A blank bar icon, menu header or lock mark means the deployed plugins are
newer than the installed theme: they reference a branding file (for example
`branding/brand.svg`) the active theme does not have yet. The doctor's
`branding` check names the missing files, and `deploy-plugins-safely` warns
about them. Update the theme so both match:

```bash
scripts/install.sh --yes --profile "$(cat ~/.local/state/aranea/profile)"
```

## Installation failed

The installer reports the exact command for restoring the previously active
theme when it can detect one. Inspect a plan before retrying:

```bash
scripts/install.sh --dry-run --yes
scripts/aranea-doctor --json
```

If `jq` or `gum` is missing, install the missing Omarchy ecosystem dependency
or use the plain CLI without the TUI. JSON mode requires `jq`; the TUI requires
both `gum` and `jq`.

## Uninstall safely

Use integration scope first:

```bash
scripts/uninstall.sh --dry-run --scope integration --yes
scripts/uninstall.sh --scope integration --yes
```

Complete removal is explicit and also removes the installed theme directory:

```bash
scripts/uninstall.sh --scope complete --replacement-theme Omarchy --yes
```

The uninstall process restores files recorded by the ownership ledger and
preserves files that were customized after installation.

## Collect useful information

For a bug report, include:

```bash
scripts/aranea-about
scripts/aranea-doctor --json
omarchy theme current
```

Also state the selected install profile, whether the problem survives a shell
restart, and whether it affects the live session or only an integration.
