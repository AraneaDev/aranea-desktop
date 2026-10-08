# Aranea Tray

`araneadev.tray` replaces Omarchy's `omarchy.tray` bar entry (the system tray widget, its app
menu and its manage popup) with an Aranea-native one.

`Tray.qml` keeps stock's buckets (`SystemTray.items`, filtered through `TrayModel.ownedByOmarchy`
and the entry's `pinned` / `hidden` id lists), click handling (left activates or opens the menu
for an `onlyMenu` item, middle secondary-activates, right opens the app menu, wheel scrolls,
right-click on the drawer arrow toggles manage), both bar orientations (the containment masks
are gone, see the drawer below), the app menu's submenu drill-down and quirks (the leading separator and root-title entry
hidden, check/radio marks, disabled dimming), and the manage popup (pin/hide per item, saved
through `updateEntryInline`). `TrayModel.js` is stock's tray bucket helpers, unchanged apart from
docs.

The plugin id is `araneadev.tray`. Pin and hide are saved under `root.moduleName`, which the bar
overwrites with the entry's own id (`araneadev.tray` once retargeted), never a literal
`"omarchy.tray"`.

**The drawer** reserves no space when collapsed: the widget is the arrow plus the pinned icons,
and it grows as the drawer slides open (600 ms, clipped). Hovering the drawer opens it, as in
stock. A left-click on the arrow holds it open until the arrow is clicked again (or IPC `close`);
the bar takes no keyboard focus and never sees outside clicks, so Esc and a click elsewhere
cannot close it. A right-click on the arrow toggles the manage panel; a drawer that was open
when manage opened stays open under it, so the card (anchored to the whole tray) never slides. There is no containment
mask any more, since nothing in the widget's box is empty.

Both popups are `Aranea.KeyboardPanelFrame` windows (layer-shell, focused when they map), anchored
as stock's were: the app menu to the clicked icon (the drawer stays slid open under a drawer
icon's menu), the manage panel to the whole tray. They draw `TrayMenuView` and `TrayManageView`.

- **App menu keys:** up/down move (wrapping, skipping separators and disabled entries), a letter
  jumps to the next entry starting with it, Enter or Space activates (drills into a submenu, or
  triggers a leaf and closes), right drills in, left or Backspace goes back, Esc closes. The
  first key only reveals the cursor. The key catcher keeps `h`/`j`/`k`/`l` as vim moves.
- **Manage keys:** up/down move between rows, left/right pick the Pin or Hide pill, Enter or
  Space toggles it, Esc closes.
- **Keyed actions:** menu rows are keyed by a per-entry serial (Quickshell does not expose the
  DBus id) plus the label, manage rows by the item id. Action index = position in `view.rows`;
  the entry at `rows[index].index` is activated only while `rows[index].key === key`.
- **Pending:** a pin or hide shows its new state at once and pulses until the settings echo
  matches it (or 3 s pass).
- **Vanishing items:** the app menu closes when its item leaves the tray; pending state of a
  vanished manage row is dropped.
- **IPC:** `omarchy-shell araneadev.tray manage`, `omarchy-shell araneadev.tray menu <index>`
  (the pinned item at `index`, else the drawer item past the pinned ones, anchored to its icon,
  with the drawer slid open under a drawer item's menu; out of range is a no-op) and
  `omarchy-shell araneadev.tray close` (which also lets a click-held drawer go).

`omarchy.clonePaths` (stock's `Tray.manifest.json` lists `TrayModel.js`) is read only by the
`omarchy-plugin-clone` dev command, to find a stock bar widget's extra files when its manifest
is a loose `*.manifest.json` beside the widget's `.qml` (there is no such reader in the shell
itself: the plugin loader, `PluginRegistry.qml`, never looks at `clonePaths`). `araneadev.tray`
is its own self-contained plugin directory with its own `manifest.json`, so `clonePaths` is
dropped from this manifest, the same way `araneadev.weather`'s was.

`TrayMenuView.qml` and `TrayManageView.qml` are the pure Aranea-native views for the app menu
and the manage panel (one view object in, one `action(name, arg)` signal out; keyed, settled
clicks and gated hover). They are tested on their own (`tests/qml/tray-menu.qml`,
`tests/qml/tray-manage.qml`).

## Integration

- `scripts/repair-shell-config` retargets `omarchy.tray` to `araneadev.tray` in `bar.layout`
  (any section), once `araneadev.tray/manifest.json` is deployed beside `shell.json`; it keeps
  the entry's `pinned` and `hidden` settings and records `araneadev.tray` in
  `cloneSourceRestores`. Tray has no `bar.centerAnchor` handling: that anchor is the clock. The
  health and bell icons place themselves right after whichever tray entry is live (tray,
  health, bell), looking for `araneadev.tray` first and falling back to `omarchy.tray`, so
  their placement is unaffected by whether the retarget has run yet.
- The Aranea bar (`araneadev.bar`'s `pinTrayToInner`) pins `araneadev.tray` to the inner edge
  of its section as stock pins `omarchy.tray`: first in the right section, whatever its place
  in `shell.json`.
- `scripts/release-shell-config` reverses the retarget.
- `scripts/deploy-plugins-safely` deploys the plugin directory.

`TrayItemButton.qml` registers each app icon with the bar click router so the
bar's drag surface can forward a completed click. Native clicks use the same
dispatch, and right-click menus open on release, after the icon's click completes.

## Validation

Run `tests/qml-behaviour.test.sh tray-widget tray-menu tray-manage`,
`tests/shell-config.test.sh`, `tests/shell-deploy.test.sh` and `tools/check-docs --root .
plugins/araneadev.tray/Tray.qml`.
