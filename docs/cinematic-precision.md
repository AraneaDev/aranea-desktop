# Cinematic Precision implementation

Approved direction: rebuild around the recognizable Aranea spider and obsidian/mint/violet identity. Static working wallpapers, refined proportional UI typography, monospace telemetry, neutral fine borders, 8px controls, 12px panels, 4px spacing rhythm. Feedback 120ms, panels 180ms, ceremony 600–900ms. Reduced motion throughout. Preserve plugin interfaces, installer profiles, wallpaper IDs, authentication and actions.

## Task 1: Artwork

Own backgrounds/, branding/marks/, branding/motifs/, branding/glyphs/ SVGs, integrations/cursor/, unlock.png. Rebuild wallpaper collection with cinematic fine luminous filaments, sparse nodes and atmospheric depth. Quiet center and bar zone, asymmetric edge clusters. Native 3840x2160 day/night/sparse/dense/dusk/monochrome and 3840x1280 ultrawide; stable manifest IDs and paths. Use imagegen for raster art (read skill); native SVG refinement for existing mark/icon system. Distinct variants, preserve recognizable spider silhouette, optically consistent primary/reduced/ceremony marks. Cursor hotspots must remain correct; both source trees must match. Record provenance and export workflow. Inspect outputs visually. Tests: assets, wallpaper, integrations relevant to cursors. Do not edit shell, scripts, tests, README, or branding/screens (controller owns these). Report in /tmp/aranea-artwork-report.md. No subagents. Leave changes uncommitted for coordinated review.

## Task 2: Shell and integrations

Controller owns colors.toml, shell.toml, all QML, GTK/Qt/browser/media/terminal/developer styling, icon integration and scripts. Implement the approved visual hierarchy, concise menu, matching popups, subtle notifications, clock-led lock and idle ceremony, short transitions. Host-owned UI must use supported theme interfaces. Add focused behavior tests where behavior changes; use existing contracts and visual QA for styling.

## Task 3: Validation and showcase

Verify all contract tests and QML; inspect renders and available live surfaces. Regenerate honest showcase captures using sanitized fixtures where necessary. Test installation profiles in isolated homes. Preserve user untracked ARANEA-THEME-PLAN.md. Do not reboot or lock out the active session for validation.

## Progress

- Initial checkout d5113bd; isolated worktree /tmp/aranea-cinematic-precision.
- Task boundary review: artwork consumes stable paths, shell consumes those same paths; only controller changes installer/tests. Each task agrees with approved direction.
- Ruling: stage all edits in an isolated feature worktree and leave them uncommitted until verification — protects the user's checkout and permits one coherent review.
- Core visual-system pass complete: palette/material tokens, shell surfaces, menu proportions, lock treatment, notifications, GTK, browser, media, terminal, and developer integrations updated. Existing raster wallpapers remain in place pending a dedicated artwork generation pass.
