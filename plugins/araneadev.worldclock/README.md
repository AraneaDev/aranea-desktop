# Aranea World Clock

Replaces Omarchy's Elsewhen bar widget with a sun-lit globe, city markers and local-day daylight strips. The existing `omarchy.elsewhen` IPC target and desktop shortcut continue to open it.

The first list is Amsterdam (home), London, UTC, New York and Los Angeles. Only Elsewhen's untouched automatic starter list is replaced. Edited lists are kept. Saved cities contain names, IANA zones, optional coordinates and one home flag; zone abbreviations and DST offsets come from the system timezone database when the panel opens and each open minute.

Click a row or use ↑/↓ to select. `a` opens search, ↑/↓ chooses a match, Enter adds it, and Esc cancels. `x` removes a non-home city, `[`/`]` reorder it, and `h` sets the selected city as home. Setting home changes only this list. Esc closes the panel; Tab switches dropdowns. Drag the globe to rotate it; it eases home after a pause. Search closes without saving when the panel closes.

The panel does no minute work while closed. Its bar tooltip retains the last sampled times until the next open.

For repeatable screenshots, open the panel and call:

```sh
quickshell ipc call omarchy.elsewhen showcase '{"nowMs":1792491180000}'
```

This displays the five seed cities at 2026-10-20 10:13 UTC. An optional `cities` array uses the saved city shape. Overrides are display only and clear on open or close.

`cities.json` and `world.json` are bundled verbatim from Omarchy's Elsewhen plugin. The city data, world geometry and seed-selection algorithm are MIT licensed, copyright Jason Fried / Omarchy. Runtime uses the bundled data and the system timezone database; it never reads the installed Elsewhen plugin. The generated globe land texture and shader are rebuilt with `tools/build-worldclock-globe` from the repository root.
