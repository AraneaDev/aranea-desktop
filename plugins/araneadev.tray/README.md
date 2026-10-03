# Aranea Tray

`araneadev.tray` replaces Omarchy's `omarchy.tray` bar entry (the system tray widget, its app
menu and its manage popup) with an Aranea-native one.

`Tray.qml` keeps stock's buckets (`SystemTray.items`, filtered through `TrayModel.ownedByOmarchy`
and the entry's `pinned` / `hidden` id lists), click handling (left activates or opens the menu
for an `onlyMenu` item, middle secondary-activates, right opens the app menu, wheel scrolls,
right-click on the drawer arrow toggles manage), both bar orientations with stock's containment
masks, the app menu's submenu drill-down and quirks (the leading separator and root-title entry
hidden, check/radio marks, disabled dimming), and the manage popup (pin/hide per item, saved
through `updateEntryInline`). `TrayModel.js` is stock's tray bucket helpers, unchanged apart from
docs.

The plugin id is `araneadev.tray`. `Tray.qml` is still the Task 3 clone: it carries stock's root
logic, markup and popups (`PopupCard`, xdg-popup) unchanged from Omarchy's Tray, so the bar entry
keeps working identically until Task 5 wires in the Aranea-native, keyboard-reachable menu and
manage views. Pin and hide are saved under `root.moduleName`, which the bar overwrites with
the entry's own id (`araneadev.tray` once retargeted), never a literal `"omarchy.tray"`.

`omarchy.clonePaths` (stock's `Tray.manifest.json` lists `TrayModel.js`) is read only by the
`omarchy-plugin-clone` dev command, to find a stock bar widget's extra files when its manifest
is a loose `*.manifest.json` beside the widget's `.qml` (there is no such reader in the shell
itself: the plugin loader, `PluginRegistry.qml`, never looks at `clonePaths`). `araneadev.tray`
is its own self-contained plugin directory with its own `manifest.json`, so `clonePaths` is
dropped from this manifest, the same way `araneadev.weather`'s was.

`TrayMenuView.qml` and `TrayManageView.qml` are the pure Aranea-native views for the app menu
and the manage panel (one view object in, one `action(name, arg)` signal out; keyed, settled
clicks and gated hover). They are tested on their own (`tests/qml/tray-menu.qml`,
`tests/qml/tray-manage.qml`) and not yet wired into `Tray.qml`. Action index = position in
`view.rows`; activate the entry at `rows[index].index` after `rows[index].key === key`.

## Integration

- `scripts/repair-shell-config` retargets `omarchy.tray` to `araneadev.tray` in `bar.layout`
  (any section), once `araneadev.tray/manifest.json` is deployed beside `shell.json`; it keeps
  the entry's `pinned` and `hidden` settings and records `araneadev.tray` in
  `cloneSourceRestores`. Tray has no `bar.centerAnchor` handling: that anchor is the clock. The
  bell and health icons, which place themselves just before whichever tray entry is live, look
  for `araneadev.tray` first and fall back to `omarchy.tray`, so their placement is unaffected
  by whether the retarget has run yet.
- `scripts/release-shell-config` reverses the retarget.
- `scripts/deploy-plugins-safely` deploys the plugin directory.

## Validation

Run `tests/shell-config.test.sh`, `tests/shell-deploy.test.sh` and `tools/check-docs --root .
plugins/araneadev.tray/Tray.qml`.
