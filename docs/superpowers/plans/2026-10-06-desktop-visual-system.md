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
- The approved follow-up adds a font-preference owner using existing fontconfig/jq dependencies; other owner behavior remains unchanged.
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

- [x] Verify master, open PR #125 and installed theme state before creating the execution branch.
- [x] Preserve the existing native Settings preview by basing the execution branch on the verified PR #125 head if that PR is still open. Include this design/plan commit by cherry-pick. If #125 is already merged, use updated master instead.
- [x] Treat those Settings changes as an existing dependency during checkpoints 1-3; checkpoint 4 adapts them to the shared roles. Do not silently downgrade the installed preview.
- [x] Keep master clean. Do not merge or release this rollout without explicit instruction.

## Coverage tracking

| Family                                          | Delivery checkpoint | Outcome / capture / checks                                                                                                                                                                        |
| ----------------------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Shared typography, chrome and controls | 1, consolidated 4 | Delivered shared font roles, glyph/label separation and neutral frames preserving configured edge widths. Shared behavior suites and independent review pass. |
| Bar and tooltips | 1 | Shared proportional tooltips and separate numeric/glyph roles; desktop capture inspected, bar suites pass. |
| Launcher and unified search | 1, completed 2 | Taller screen-relative row viewport; menu/root/submenu/search/input captures inspected. Normal/short-screen geometry and override regressions pass. |
| Audio and network | 1 | Neutral frames and UI/technical/icon roles; audio/network captures and behavior suites pass. |
| Bluetooth and VPN | 2 | Compact native headings, UI labels, mono session data and dedicated icons. bluetooth/vpn captures; 78/132 QML checks pass. |
| Displays and power | 2 | Shared typography, numeric captions and split profile glyphs. monitor/power captures; 109/72 QML checks pass. |
| Tray and workspaces | 2 | Native app captions, compact tray management and distinct workspace glyph/value roles. tray/tray-manage/workspaces captures; keyed suites pass. |
| Apps, favorites, recent, submenus and input | 2 | Shared MenuStyle presentation retained across command variants; apps/favorites/recent/menu-submenu/menu-input captures and menu suites pass. |
| Notifications | 3 | UI message text, mono timestamps, neutral ordinary cards and preserved urgency. notifications/notifications-empty captures; grouping/keyed/fit suites pass. |
| Health, Agents and updates | 3 | UI headings with technical telemetry, money and counts; neutral frames. health/agents/updates captures and focused suites pass. |
| Clipboard, emoji and image picker | 3 | UI picker labels, technical code previews and dedicated emoji glyphs. clipboard/emojis/image-picker captures; masking, keyed and pointer suites pass. |
| Clock and weather | 3 | Shared label/value/icon roles and separate weather edit glyph. clock/weather captures; 111/132 QML checks pass. |
| Settings and OSD | 4 | Searchable Interface/Monospace preferences, samples and explicit Apply/Reset; compact scrollable Settings and shared OSD roles. settings/settings-scaling/osd captures; 1296 scroll checks pass. |
| Authentication, lock and idle | 4 | Shared text roles with dedicated auth glyphs; secure lifecycle unchanged. polkit (cancelled request), inert lock and dawn captures inspected; auth/lock tests pass. |
| Boot and identity assets | 4 | Retained mint spider and restrained ceremonial treatment after inert plymouth/dawn/lock inspection. Identity and boot render contracts pass. |
| GTK, Qt, file manager and browser | 4 | Retained generated palettes and native application font ownership. File-manager visual capture inspected; GTK/Qt/browser template and integration contracts pass. Qt/browser integrations were not enabled solely for capture. |
| Terminal, editor/developer tools and media/Cava | 4 | Retained generated palette and monospace content roles. btop/neovim captures inspected; terminal/developer/media token and integration contracts pass. |
| Icons, cursors and wallpaper variants | 4 | Retained existing geometry and obsidian/mint/violet assets after icon/cursor and all eight wallpaper visual review. Asset, icon and token contracts pass. |

The user approved continuing the remaining families together. Checkpoints 2–4 were consolidated into the installed PR #126 preview; unchanged integrations retain native content fonts and the existing generated palette.

## Cross-checkpoint acceptance

- [x] Every component family has a reviewed outcome, not just Settings or the first pilot.
- [x] Font overrides, icon glyphs, technical data, owner actions, keyboard/pointer contracts and secure lifecycle remain intact.
- [x] Resolution/scale matrix and reduced motion pass at each affected checkpoint.
- [x] Published captures represent the normal desktop flow and restore user state.
- [x] Each checkpoint passes the complete gate and independent review before publishing its draft PR/installed preview.

## Consolidated verification record

Seven focused source commits deliver font preferences/launcher, shared chrome, controls, information/pickers/time, secure surfaces and documentation. Independent review found a swapped fingerprint glyph/instruction font binding; it was fixed and re-reviewed. The launcher-only environment override is scoped to MenuStyle, and explicit owner readback refreshes newly created font files. A runner-only QtTest binding in the emoji pointer fixture was made explicit after an intermittent full-run failure; the 36 interaction assertions remain unchanged.

Sixteen component fixtures were inspected at 1×, 2.5× and 2.667×, including 320-logical-pixel layouts; Settings wide/narrow rendering and constrained scroll contracts also pass. Normal desktop captures cover all 37 gallery surfaces, with lock/boot views using inert renderers and authentication captured without entering credentials. The hero retains 31 frames. Installed owner and monitor state was compared with the backup; default font preferences remain absent until explicit Apply.

The final complete gate passes all eight stages: format, lint, docs, validate, strict QML, QML behavior, shell/JavaScript tests and smoke. The gallery contract confirms 37 surfaces and the 31-frame hero. Authentication capture allows bounded slow PAM startup and cancels without credentials. Owner preferences, display configuration, focus and workspace were preserved.
