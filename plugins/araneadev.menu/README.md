# Aranea menu

`araneadev.menu` is the command menu and its bar launcher. The manifest exposes
`Menu.qml` as `menu` and `BarWidget.qml` as `bar-widget`.

## Responsibilities

- Load and merge the shipped menu model with user overrides.
- Resolve routes, aliases, parent paths, and visible descendants.
- Batch guard checks so rows share command and package readers.
- Search applications and menu rows while preserving favorites and recents.
- Compose the menu window, card chrome, root tiles, result list, and app
  library.

`Menu.qml` owns menu state and persistence. `MenuWindow.qml` owns the window
contract. `MenuModel.js` remains a stable QML-compatible facade while focused
modules own history, search, and tree traversal.

## Logic boundaries

- `MenuHistory.js` owns favorites and recent-app persistence.
- `MenuSearch.js` owns matching and ranking.
- `MenuTree.js` owns routes, ancestry, visibility, and breadcrumbs.
- `MenuPresentation.js` owns display labels and row projections.
- QML owns focus, navigation, and user interaction.

Shared keyboard and panel behavior comes from `araneadev.shared`.

## Validation

Run `tests/qml-behaviour.test.sh menu-components menu-window-components menu`
and the menu JS suites.
