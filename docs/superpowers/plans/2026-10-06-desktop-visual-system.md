# Aranea desktop visual system rollout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved whole-desktop visual and UX refinement in four installed checkpoints.

**Architecture:** Share typography and opt-in presentation through the existing component kit; migrate each host family deliberately. Every checkpoint is independently testable and reviewable.

**Tech Stack:** Qt Quick/QML, Quickshell, Omarchy shell, JavaScript, Bash and existing token generation.

**Spec:** [../specs/2026-10-06-desktop-visual-system-design.md](../specs/2026-10-06-desktop-visual-system-design.md)

**Prerequisite:** Specification approved in conversation. Planning branch docs/desktop-visual-system at d49f119; implementation should use an isolated named feature branch.

## Global constraints

- Keep the obsidian palette, mint interaction, violet identity, spider mark and filament motifs.
- UI text defaults to the system `sans-serif` alias, without bundling a new font.
- Technical text uses the desktop monospace family.
- An explicit override takes precedence over the proportional default.
- Keep icon glyphs on their existing dedicated font paths.
- Use existing host font-size tokens and `Style.space` scaling.
- Preserve the user's panel corner radius and border-width preferences.
- All motion respects reduced motion and has an equally clear static state.
- Preserve backend commands, IPC, routes, dmenu results, authentication protocols, clipboard masking, notification ownership, persistent settings and owner readback.
- This design introduces no new runtime dependency or backend feature.
- Feature hosts own lifecycle, focus, selection, scrolling and owner operations.
- Update canonical tokens/templates and regenerate projections. Never edit `/usr/share/omarchy`.
- Cosmetic work uses existing meaningful behavior/geometry tests and visual inspection. Add a failing regression test before changing behavior or fixing an uncovered bug; do not write tests that duplicate decoration.
- Document root QML properties/signals/functions inline; format owned QML files with `/usr/lib/qt6/bin/qmlformat -i`.
- Keep each task in a focused commit. Preserve clean master, independent review and installed preview checkpoints.

## Execution sequence

1. [Representative preview](2026-10-06-desktop-visual-preview.md): shared foundation, bar, launcher, audio and network.
2. [Everyday controls](2026-10-06-desktop-everyday-controls.md): Bluetooth, VPN, displays, power, tray, workspaces and command variants.
3. [Information and pickers](2026-10-06-desktop-information-pickers.md): notifications, Health, Agents, updates, clipboard, emoji, image picker, clock and weather.
4. [Complete desktop](2026-10-06-desktop-complete-system.md): Settings, OSD, authentication, lock/idle, boot, application integrations, assets and consolidation.

Read each child plan with the approved spec. Execute task-by-task inline unless
the user chooses delegation; do not spawn implementation agents merely because
multiple tasks exist. Independent review uses the explicitly invoked review skill.

## Branch and dependency handling

- [ ] Verify master, open PR #125 and installed theme state before creating the execution branch.
- [ ] Preserve the existing native Settings preview by basing the execution branch on the verified PR #125 head if that PR is still open. Include this design/plan commit by cherry-pick. If #125 is already merged, use updated master instead.
- [ ] Treat those Settings changes as an existing dependency during checkpoints 1-3; checkpoint 4 adapts them to the shared roles. Do not silently downgrade the installed preview.
- [ ] Keep master clean. Do not merge or release this rollout without explicit instruction.

## Coverage tracking

| Family                                          | Delivery checkpoint | Outcome / capture / checks |
| ----------------------------------------------- | ------------------- | -------------------------- |
| Shared typography, chrome and controls          | 1, consolidated 4   | Pending execution          |
| Bar and tooltips                                | 1                   | Pending execution          |
| Launcher and unified search                     | 1, completed 2      | Pending execution          |
| Audio and network                               | 1                   | Pending execution          |
| Bluetooth and VPN                               | 2                   | Pending execution          |
| Displays and power                              | 2                   | Pending execution          |
| Tray and workspaces                             | 2                   | Pending execution          |
| Apps, favorites, recent, submenus and input     | 2                   | Pending execution          |
| Notifications                                   | 3                   | Pending execution          |
| Health, Agents and updates                      | 3                   | Pending execution          |
| Clipboard, emoji and image picker               | 3                   | Pending execution          |
| Clock and weather                               | 3                   | Pending execution          |
| Settings and OSD                                | 4                   | Pending execution          |
| Authentication, lock and idle                   | 4                   | Pending execution          |
| Boot and identity assets                        | 4                   | Pending execution          |
| GTK, Qt, file manager and browser               | 4                   | Pending execution          |
| Terminal, editor/developer tools and media/Cava | 4                   | Pending execution          |
| Icons, cursors and wallpaper variants           | 4                   | Pending execution          |

Pending execution is a progress state, not an unspecified task: each row maps
to the concrete files, actions and checks in its child plan. Record an inspected
unchanged component only with the visual evidence and reason it already meets
the approved direction.

## Cross-checkpoint acceptance

- [ ] Every component family has a reviewed outcome, not just Settings or the first pilot.
- [ ] Font overrides, icon glyphs, technical data, owner actions, keyboard/pointer contracts and secure lifecycle remain intact.
- [ ] Resolution/scale matrix and reduced motion pass at each affected checkpoint.
- [ ] Published captures represent the normal desktop flow and restore user state.
- [ ] Each checkpoint passes the complete gate and independent review before publishing its draft PR/installed preview.
