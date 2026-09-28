# Aranea documentation

Aranea is a cinematic Omarchy desktop theme: obsidian surfaces, mint signal
lines, violet accents, quiet wallpapers, and a shell that treats status as
part of the interface.

## Choose a path

| If you are... | Start here |
| --- | --- |
| Installing Aranea | [Getting started](getting-started.md) |
| Exploring the experience | [Features](features.md) |
| Changing behavior | [Configuration](configuration.md) |
| Fixing an installation | [Troubleshooting](troubleshooting.md) |
| Writing automation or an agent | [Agent interface](agent-interface.md) |
| Looking for icons | [Icon gallery](icons.md) |
| Working on the project | [Development](development.md) |

## Command map

```text
./installer                         human-guided TUI
scripts/install.sh                  install/update CLI
scripts/uninstall.sh                remove integration or everything
scripts/aranea-doctor               inspect and repair health
scripts/aranea-wallpaper            list and select wallpapers
scripts/aranea-integrations         inspect or toggle integrations
scripts/aranea-about                version and active-theme summary
```

Agents should use the same commands with `--json` where supported. The
[agent interface](agent-interface.md) documents the JSONL protocol and exit
codes.

## Design vocabulary

The public visual principles are collected in [Visual language](visual-language.md).
The implementation is organized into theme, shell, integration, and tooling
layers; see [Development](development.md) for the repository map.
