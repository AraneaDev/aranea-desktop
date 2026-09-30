// Favourites, recents and the uninstall prompt of the Aranea menu
// (MenuAppHistory): pinned and recent app ids persist to menu.json in the
// Aranea state directory, and rowsFor() builds the generated Apps rows.
// Menu.qml owns one as `appHistory`.
import Quickshell
import Quickshell.Io
import QtQuick
import "MenuModel.js" as MenuModel

Item {
  id: history

  // Aranea state directory (menu.json lives in it).
  property string stateRoot: ""
  // Whether the menu is showing; closing it clears the uninstall prompt.
  property bool opened: false
  // Maximum number of pinned apps kept.
  readonly property int favoriteAppLimit: 12
  // Maximum number of recent apps kept.
  readonly property int recentAppLimit: 12
  // Pinned app ids, saved to the state file.
  property var favoriteAppIds: []
  // Recently launched app ids, newest first, saved to the state file.
  property var recentAppIds: []
  // Favourites and recents on disk, so they survive shell restarts.
  readonly property string appHistoryPath: history.stateRoot + "/menu.json"
  // Whether the uninstall confirmation dialog is showing.
  property bool deleteConfirmOpen: false
  // App awaiting uninstall confirmation ({appId, label}), or null.
  property var deleteTarget: null

  // Emitted when the pinned or recent ids changed (the Apps rows need rebuilding).
  signal updated
  // Asks the menu to show TEXT on its hint line.
  signal noticeRequested(string text)

  onOpenedChanged: {
    if (!opened) {
      history.deleteConfirmOpen = false
      history.deleteTarget = null
    }
  }

  // Loads the favourites and recents; a missing or broken file means none.
  FileView {
    id: appHistoryFile
    path: history.appHistoryPath
    // Load before anything can pin or launch, so the file never overwrites newer changes.
    blockLoading: true
    atomicWrites: true
    printErrors: false
    onLoaded: history.applyAppHistory(text())
    onLoadFailed: history.applyAppHistory("")
  }

  // Makes sure the state directory exists before the first write.
  Process {
    running: history.stateRoot !== ""
    command: ["mkdir", "-p", history.stateRoot]
  }

  // Applies the state file's favourites and recents.
  function applyAppHistory(raw: string): void {
    var parsed = MenuModel.parseAppHistory(raw, history.favoriteAppLimit, history.recentAppLimit)
    history.favoriteAppIds = parsed.favorites
    history.recentAppIds = parsed.recent
    history.updated()
  }

  // Writes pinned and recent app ids to the state file.
  function saveAppHistory(): void {
    appHistoryFile.setText(MenuModel.serializeAppHistory(history.favoriteAppIds, history.recentAppIds, history.favoriteAppLimit, history.recentAppLimit))
  }

  // Pins or unpins an app and saves; a 13th pin is refused with a notice.
  function toggleFavorite(appId: string): void {
    var result = MenuModel.toggleFavoriteApp(history.favoriteAppIds, appId, history.favoriteAppLimit)
    if (result.refused) {
      history.noticeRequested("12 FAVOURITES · UNPIN ONE FIRST")
      return
    }
    history.favoriteAppIds = result.ids
    history.saveAppHistory()
    history.updated()
  }

  // Moves an app to the front of Recent and saves.
  function recordRecent(appId: string): void {
    history.recentAppIds = MenuModel.recordRecentApp(history.recentAppIds, appId, history.recentAppLimit)
    history.saveAppHistory()
    history.updated()
  }

  // The apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries) instead of a bash enumeration, so they carry image
  // icons, launch feedback, and uninstall support like the launcher.
  function rowsFor(library: var): var {
    if (!library)
      return []
    var rows = library.sortedEntries("")
    // Uninstalled apps must not use up favourite or recent slots; an app
    // library that has not loaded yet (no rows) must not wipe the lists.
    var installed = rows.map(function (r) {
      return String(r.entry.id || "")
    })
    var favorites = MenuModel.pruneAppIds(history.favoriteAppIds, installed)
    var recent = MenuModel.pruneAppIds(history.recentAppIds, installed)
    if (rows.length > 0 && (favorites.length !== history.favoriteAppIds.length || recent.length !== history.recentAppIds.length)) {
      history.favoriteAppIds = favorites
      history.recentAppIds = recent
      history.saveAppHistory()
    }
    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId)
        continue
      var subtext = library.entrySubtext(entry)
      var aliases = subtext ? [subtext] : []
      try {
        if (entry.keywords && typeof entry.keywords.join === "function")
          aliases = aliases.concat(entry.keywords)
      } catch (e) {}
      appRows.push({
        id: "apps." + appId,
        parent: "apps",
        kind: "app",
        icon: "",
        appIcon: String(entry.icon || ""),
        appId: appId,
        label: library.entryName(entry),
        title: "",
        target: "",
        description: subtext,
        action: "",
        provider: "",
        aliases: aliases,
        when: "",
        checked: "",
        order: 0
      })
    }
    var favoriteRows = MenuModel.appRowsForIds(appRows, history.favoriteAppIds, "apps.favorites", "apps.favorites")
    var recentRows = MenuModel.appRowsForIds(appRows, history.recentAppIds, "apps.recent", "apps.recent")
    // Keep both generated destinations present even when they are empty. This
    // gives direct routes and screenshots a deliberate empty state, and lets
    // the sections become useful immediately after the first pin or launch.
    appRows.unshift({
      id: "apps.favorites",
      parent: "apps",
      kind: "menu",
      icon: "",
      appIcon: "",
      appId: "",
      label: "Favorites",
      title: "",
      target: "",
      description: "Pinned applications",
      action: "",
      provider: "",
      aliases: ["favorite", "favorites", "pinned"],
      when: "",
      checked: "",
      order: 0
    })
    appRows = appRows.slice(0, 1).concat(favoriteRows, appRows.slice(1))
    appRows.unshift({
      id: "apps.recent",
      parent: "apps",
      kind: "menu",
      icon: "󰋚",
      appIcon: "",
      appId: "",
      label: "Recent",
      title: "",
      target: "",
      description: "Recently launched applications",
      action: "",
      provider: "",
      aliases: ["recent", "history"],
      when: "",
      checked: "",
      order: 0
    })
    appRows = appRows.slice(0, 1).concat(recentRows, appRows.slice(1))

    return appRows
  }

  // Opens the uninstall prompt for an app.
  function requestDelete(appId: string, label: string): void {
    history.deleteTarget = {
      appId: appId,
      label: label
    }
    history.deleteConfirmOpen = true
  }

  // Closes the uninstall prompt without uninstalling.
  function cancelDelete(): void {
    history.deleteConfirmOpen = false
    history.deleteTarget = null
  }

  // Closes the uninstall prompt and returns its target ({appId, label}) or null.
  function takeDeleteTarget(): var {
    var target = history.deleteTarget
    history.deleteConfirmOpen = false
    history.deleteTarget = null
    return target
  }
}
