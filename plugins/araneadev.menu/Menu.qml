// Aranea menu: the plugin's "menu" entry point (manifest.json), summoned by
// omarchy-shell. Renders the JSONC command menu with app launcher, providers
// and guards, and also serves dmenu-style select/input requests.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea
import "MenuModel.js" as MenuModel
import "MenuLayout.js" as MenuLayout

Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  // Scoped shell object from the host; supplies the shared appLibrary when present.
  property var shell: null
  // Public copy of this plugin's manifest, set by the host.
  property var manifest: null

  // Plugin lifecycle hooks. The host calls open(payloadJson) after
  // `omarchy-shell shell summon araneadev.menu ...` and close() when hidden.
  // Favorites or Recent route waiting for the generated Apps rows; resolved by resolvePendingAppsRoute.
  property string pendingInitialMenu: ""

  // The rows shown in the menu (display order), read by the window.
  readonly property alias displayModel: rowsModel
  // Both menu files have reported: a pending route can only resolve then, or
  // it would resolve against a half-built menu and fall back to the root.
  readonly property bool menuSourcesReady: sources.ready
  // Whether to create the on-screen window (MenuWindow.qml); tests switch it off.
  property bool windowEnabled: true
  // The window, once created; null offscreen.
  property var view: null
  // Runs a detached shell command; tests replace it with a recorder.
  property var run: function (command) {
    Util.execDetached(command)
  }
  // Screen width from the window (1920 offscreen).
  readonly property int screenWidth: root.view ? root.view.width : 1920
  // Screen height from the window (1080 offscreen).
  readonly property int screenHeight: root.view ? root.view.height : 1080
  // The window's frozen card top, or -1.
  readonly property int viewCardTop: root.view ? root.view.cardTop : -1
  // The window's row-height ceiling for this opening, or -1.
  readonly property int viewMaxRowsHeight: root.view ? root.view.maxRowsHeight : -1
  // Key hint line for the current state (a notice replaces it for a moment).
  readonly property string hint: root.notice || MenuModel.hintText({
    root: root.fullRootHeader,
    filter: !!root.filterText.trim(),
    dmenu: root.dmenuActive,
    input: root.mode === "input",
    count: displayModel.count,
    appRow: root.cursorRowIsApp()
  })

  // Freezes the card's top edge in the window (no-op offscreen).
  function freezeCardTop(): void {
    if (root.view)
      root.view.freezeCardTop()
  }

  // Gives the window's key handler the keyboard focus (no-op offscreen).
  function focusKeys(): void {
    if (root.view)
      root.view.focusKeys()
  }

  // Scrolls the cursor row into view with a peek of its neighbour (window).
  function revealCursor(): void {
    if (root.view)
      root.view.revealCursor()
  }

  // One key map for the menu (the window forwards its key presses here).
  function handleKey(event): void {
    if (history.deleteConfirmOpen) {
      if (root.view && root.view.deleteConfirmHandleKey(event))
        event.accepted = true
      return
    }

    if (event.key === Qt.Key_Delete) {
      root.requestDeleteSelected()
      event.accepted = true
    } else if (event.key === Qt.Key_Escape) {
      if (root.filterText)
        root.setFilter("")
      else
        root.cancel()
      event.accepted = true
    } else if ((event.modifiers & Qt.ControlModifier) && event.key >= Qt.Key_1 && event.key <= Qt.Key_3 && !root.dmenuActive) {
      root.activateTile(root.style.rootTiles[event.key - Qt.Key_1])
      event.accepted = true
    } else if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier) && !root.dmenuActive) {
      if (root.cursorActive && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count) {
        var pinRow = displayModel.get(root.selectedIndex)
        if (pinRow.kind === "app" && pinRow.appId)
          root.toggleFavoriteApp(pinRow.appId)
      }
      event.accepted = true
    } else if (Util.editsFilter(event, root.filterText)) {
      root.setFilter(Util.editedFilter(event, root.filterText))
      event.accepted = true
    } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {
      root.goBack()
      event.accepted = true
    } else if (event.key === Qt.Key_Up) {
      root.select(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Down) {
      root.select(1)
      event.accepted = true
    } else if (event.key === Qt.Key_PageUp) {
      root.select(-6)
      event.accepted = true
    } else if (event.key === Qt.Key_PageDown) {
      root.select(6)
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
      if (root.dmenuActive) {
        if (root.mode === "input")
          root.applyDmenuSelection(root.filterText)
        else if (displayModel.count > 0)
          root.activateIndex(root.cursorActive ? root.selectedIndex : 0, false)
      } else if (root.cursorActive)
        root.activateIndex(root.selectedIndex, false)
      else if (displayModel.count > 0)
        root.cursorActive = true
      event.accepted = true
    } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
      root.setFilter(root.filterText + event.text)
      event.accepted = true
    }
  }

  Component.onCompleted: {
    root.loadApps()
    if (!root.windowEnabled)
      return
    var windowComponent = Qt.createComponent(Qt.resolvedUrl("MenuWindow.qml"))
    if (windowComponent.status === Component.Ready)
      root.view = windowComponent.createObject(root, {
        root: root
      })
    else
      console.warn("menu: window failed to load:", windowComponent.errorString())
  }

  // Opens the menu at the payload's route, or as a dmenu picker when mode is select/input.
  function open(payloadJson: string): void {
    root.notice = ""
    var payload = ({})
    try {
      payload = JSON.parse(payloadJson || "{}")
    } catch (e) {
      payload = ({})
    }

    if (payload.fontFamily)
      root.style.fontFamily = payload.fontFamily

    if (payload.mode === "select" || payload.mode === "input") {
      root.openDmenu(payload)
    } else {
      root.openRoute(payload.initialMenu || payload.menu || "root")
    }
  }

  // Hides the menu, answering a pending dmenu request as cancelled.
  function close(): void {
    root.cancel()
  }

  // Reloads both JSONC menu files and returns "ok".
  function refresh(): string {
    sources.reload()
    return "ok"
  }

  // Liveness check: always returns "ok".
  function ping(): string {
    return "ok"
  }

  // Whether the menu is showing; clearing it closes the panel.
  property bool opened: false
  // "menu" for the command menu, "select" or "input" for a dmenu request.
  property string mode: "menu"
  // True while serving a dmenu (select or input) request.
  readonly property bool dmenuActive: mode === "select" || mode === "input"
  // Prompt text shown in the header for a dmenu request.
  property string dmenuPrompt: ""
  // Raw dmenu option strings ("label", "glyph\tlabel" or "glyph\tlabel\tsubtext").
  property var dmenuOptions: []
  // File a dmenu request's answer is written to.
  property string selectionFile: ""
  // File touched when a dmenu request finishes (answered or cancelled).
  property string doneFile: ""
  // Requested dmenu card width, in unscaled units.
  property int dmenuWidth: 300
  // Requested dmenu row-list height cap, in unscaled units (0 for none).
  property int dmenuMaxHeight: 0
  // Whether a dmenu request is still waiting for its answer.
  property bool requestActive: false
  // What the empty list shows for the active menu (its own provider only).
  readonly property var emptyStateInfo: MenuModel.emptyState({
    loading: !!providers.loadingMenus[root.activeMenu],
    error: !!providers.errorMenus[root.activeMenu],
    filter: root.filterText
  })
  // Set once the JSONC sources have been merged; the panel stays hidden until then.
  property bool rowsLoaded: false
  // Id of the submenu being shown.
  property string activeMenu: "root"
  // Current search text (or the typed value in input mode).
  property string filterText: ""
  // Index of the cursor row in displayModel.
  property int selectedIndex: 0
  // Whether the cursor row is highlighted and Enter activates it.
  property bool cursorActive: false
  // Bumped on every open; compared with applySerial when a result write finishes.
  property int requestSerial: 0
  // requestSerial at the time a selection was applied.
  property int applySerial: 0
  // All menu items by id (JSONC, app and provider rows).
  property var items: ({})
  // Item ids in declaration order.
  property var itemOrder: []
  // Previously visited submenu ids, popped by goBack().
  property var navStack: []
  // Last generated Apps rows, including the Favorites and Recent submenus.
  property var appRows: []
  // One-off message that replaces the key hints until noticeTimer clears it.
  property string notice: ""

  // Clears the hint-line notice three seconds after showNotice.
  Timer {
    id: noticeTimer
    interval: 3000
    onTriggered: root.notice = ""
  }

  // Shared application engine (entries, hidden filters, icons, launch,
  // removal), owned by the shell and also used by the standalone launcher.
  readonly property var appLibrary: root.shell && root.shell.appLibrary ? root.shell.appLibrary : localAppLibrary

  // Older Omarchy shells inject a scoped shell object without its AppLibrary
  // capability. Keep the menu usable on those hosts by reading the same
  // DesktopEntries source locally instead of turning Apps into an empty page.
  MenuAppLibrary {
    id: localAppLibrary
    owner: root
  }

  // Favourites, recents and the uninstall prompt; builds the Apps rows.
  MenuAppHistory {
    id: history
    stateRoot: Aranea.RuntimePaths.araneaStateRoot
    opened: root.opened
    onUpdated: root.loadApps()
    onNoticeRequested: function (text) {
      root.showNotice(text)
    }
  }
  // Favourites, recents and the uninstall prompt (the window reads it).
  readonly property alias appHistory: history
  // Pinned app ids.
  readonly property alias favoriteAppIds: history.favoriteAppIds

  // Regenerates the Apps rows (apps, Favorites, Recent) from the app library,
  // merges them into the items and resolves a waiting Favorites/Recent route.
  // The Apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries), so they carry image icons, launch feedback and uninstall.
  function loadApps(): void {
    if (!root.appLibrary)
      return
    root.appRows = history.rowsFor(root.appLibrary)
    var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, root.appRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    root.rebuildIfOpen()
    root.resolvePendingAppsRoute()
  }

  // Whether the cursor row is an app (the hint line then offers ^P PIN).
  function cursorRowIsApp(): bool {
    return root.cursorActive && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count && displayModel.get(root.selectedIndex).kind === "app"
  }

  // Shows text on the hint line for three seconds.
  function showNotice(text: string): void {
    root.notice = text
    noticeTimer.restart()
  }

  // Pins or unpins an app (a 13th pin is refused with a notice).
  function toggleFavoriteApp(appId: string): void {
    history.toggleFavorite(appId)
  }

  // Moves an app to the front of Recent.
  function recordRecentApp(appId: string): void {
    history.recordRecent(appId)
  }
  // True on the unfiltered root menu, which shows the large header, tiles and footer.
  readonly property bool fullRootHeader: !root.dmenuActive && root.activeMenu === "root" && !root.filterText.trim()

  // Colors, fonts, metrics, branding paths, root tiles and the context band.
  MenuStyle {
    id: menuStyle
    opened: root.opened
    fullRootHeader: root.fullRootHeader
  }
  // The menu's style (read by the window as root.style.x).
  readonly property alias style: menuStyle
  // Whether search results are split into current-menu and drilldown sections.
  property bool searchDivider: false
  // Bumped after each display rebuild so row-height bindings recompute.
  property int layoutSerial: 0
  // Card width: depends on mode and menu, capped to the screen.
  property int cardWidth: Math.min(root.dmenuActive ? Math.max(Style.space(root.dmenuWidth), Style.space(420)) : root.fullRootHeader ? Style.space(640) : ((root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "style.font") ? Style.space(560) : Style.space(480)), root.screenWidth - Style.gapsOut * 2)
  // Height given to the row list for the current rows.
  property int visibleRowsHeight: root.dmenuActive ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText) : rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)
  // Total card height, capped to the screen.
  property int cardHeight: root.dmenuActive ? Math.min(root.style.contentMargin * 2 + root.style.headerHeight + (mode === "input" ? 0 : root.style.contentSpacing + visibleRowsHeight), root.screenHeight - Style.gapsOut * 2) : Math.min(root.style.contentMargin * 2 + (root.fullRootHeader ? root.style.rootHeaderHeight : root.style.headerHeight) + root.style.contentSpacing + root.style.rootExtrasHeight + visibleRowsHeight, root.screenHeight - Style.gapsOut * 2)

  // Answers a pending dmenu request: writes the selection (unless null) and touches the done file.
  function finishRequest(selection) {
    if (!root.requestActive || !root.doneFile) {
      root.opened = false
      return
    }

    var activeSelectionFile = root.selectionFile
    var activeDoneFile = root.doneFile
    root.requestActive = false
    root.selectionFile = ""
    root.doneFile = ""

    if (selection === null || selection === undefined) {
      resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(activeDoneFile)]
    } else {
      resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(selection) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    }
    resultProc.running = true
  }

  // Runs a shell command detached; anything but a non-empty string is ignored.
  function runAction(action): void {
    if (typeof action !== "string" || !action.trim())
      return
    root.run(action)
  }

  // Handles a root tile click or Ctrl+1..3: open Files, a terminal or Setup.
  function activateTile(tile): void {
    if (!tile)
      return
    if (tile.id === "tile.files") {
      root.runAction("xdg-open " + Util.shellQuote(Quickshell.env("HOME")))
      root.cancel()
      return
    }
    if (tile.id === "tile.terminal") {
      root.runAction("xdg-terminal-exec")
      root.cancel()
      return
    }
    if (tile.id === "tile.setup") {
      root.openRoute("setup")
      return
    }
  }

  // Menu rows only surface their detail while a search is narrowing them;
  // dmenu rows carry caller-supplied subtext that must always be visible.
  function rowHeightForDetail(detail: string): int {
    return (root.fullRootHeader || root.filterText || root.dmenuActive) && detail ? root.style.detailRowHeight : root.style.baseRowHeight
  }

  // Each display row's section and height, for MenuLayout.
  function displayRowMetrics(): var {
    var rows = []
    for (var i = 0; i < displayModel.count; i++) {
      var row = displayModel.get(i)
      rows.push({
        section: row.section,
        height: root.rowHeightForDetail(row.detail)
      })
    }
    return rows
  }

  // The style numbers MenuLayout needs.
  function layoutMetrics(): var {
    return {
      baseRowHeight: root.style.baseRowHeight,
      rowSpacing: root.style.rowSpacing,
      rowPeek: root.style.rowPeek,
      dividerHeight: root.style.dividerHeight
    }
  }

  // Height the card can devote to rows (MenuLayout.availableRowsHeight). Uses
  // root.viewCardTop rather than effectiveCardTop: the centered top is derived
  // from the card height, which this value feeds. The root surface is a
  // shorter command viewport, so its header, band, tiles and footer read as
  // one composition.
  function availableRowsHeight(): int {
    return MenuLayout.availableRowsHeight({
      screenHeight: root.screenHeight,
      cardTop: root.viewCardTop,
      gapsOut: Style.gapsOut,
      contentMargin: root.style.contentMargin,
      headerHeight: root.fullRootHeader ? root.style.rootHeaderHeight : root.style.headerHeight,
      contentSpacing: root.style.contentSpacing,
      rootExtrasHeight: root.style.rootExtrasHeight,
      maxRowsHeight: root.viewMaxRowsHeight,
      ceiling: root.fullRootHeader ? Style.space(250) : Math.round(root.screenHeight * 0.7)
    })
  }

  // Row-list height for the menu (arguments are unused; they only make the binding re-evaluate).
  function rowListHeight(_serial: int, _count: int, _filter: string, _divider: bool): int {
    if (displayModel.count === 0)
      return root.style.emptyStateHeight
    var metrics = root.layoutMetrics()
    return MenuLayout.foldedListHeight(MenuLayout.menuRowTotals(root.displayRowMetrics(), metrics), root.availableRowsHeight(), metrics)
  }

  // Row-list height for a dmenu request (arguments only trigger re-evaluation).
  function dmenuRowListHeight(_serial: int, _count: int, _filter: string): int {
    if (root.mode === "input")
      return 0
    if (displayModel.count === 0)
      return root.style.baseRowHeight
    var available = root.availableRowsHeight()
    if (root.dmenuMaxHeight > 0)
      available = Math.min(available, Style.space(root.dmenuMaxHeight))
    var metrics = root.layoutMetrics()
    return MenuLayout.foldedListHeight(MenuLayout.plainRowTotals(root.displayRowMetrics(), metrics.rowSpacing), available, metrics)
  }

  // Returns the item with this id, or null.
  function item(id: string): var {
    return root.items[id] || null
  }

  // Merge defaults + user extension. Later entries override earlier ones
  // on a per-key basis (so the user can tweak label/icon/action without
  // re-declaring the whole row).
  function rebuildItemsFromSources(): void {
    var mergedMenu = sources.merge()
    providers.reset()
    root.items = mergedMenu.items
    root.itemOrder = mergedMenu.itemOrder
    root.rowsLoaded = true
    guards.evaluate(root.items)
    // The generated Apps rows (apps, Favorites, Recent) are not in the JSONC
    // sources: merge them back, so a rebuild (the user menu file loading after
    // the default one) keeps an open generated menu instead of resetting to root.
    if (root.appRows.length > 0)
      providers.start("apps")
    if (root.opened) {
      root.rebuildDisplay()
      if (!root.dmenuActive) {
        if (root.filterText.trim())
          providers.loadForSearch(root.activeMenu)
        else
          providers.load(root.activeMenu)
      }
    }
    if (root.pendingInitialMenu) {
      providers.start("apps")
      root.resolvePendingAppsRoute()
    }
  }

  // Bash providers that fill submenus on demand; their rows swap into the items.
  MenuProviders {
    id: providers
    items: root.items
    itemOrder: root.itemOrder
    onAppsRequested: root.loadApps()
    onRowsReady: function (menuId, rows) {
      root.applyProviderRows(menuId, rows)
    }
  }

  // Swaps a provider's rows in under MENUID, rebuilds, and lets a running search load more.
  function applyProviderRows(menuId: string, rows: var): void {
    var merged = MenuModel.swapProviderRows(root.items, root.itemOrder, menuId, rows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    root.rebuildIfOpen()
    if (root.filterText.trim())
      providers.loadForSearch(root.activeMenu)
  }

  // Refills displayModel with the dmenu options that match the filter.
  function rebuildDmenuDisplay(): void {
    displayModel.clear()
    root.searchDivider = false

    if (root.mode === "input") {
      layoutSerial += 1
      return
    }

    var query = root.filterText.trim().toLowerCase()
    for (var i = 0; i < root.dmenuOptions.length; i++) {
      // An option is "<label>", "<glyph>\t<label>", or
      // "<glyph>\t<label>\t<subtext>". The glyph never comes back with the
      // selection; the subtext renders under the label, filters alongside it,
      // and returns with the selection as a stable key for same-named rows.
      var parts = String(root.dmenuOptions[i] || "").split("\t")
      var icon = parts.length > 1 ? parts.shift() : ""
      var label = parts.shift() || ""
      var detail = parts.join("\t")
      if (query && label.toLowerCase().indexOf(query) < 0 && detail.toLowerCase().indexOf(query) < 0)
        continue
      displayModel.append({
        itemId: "dmenu." + i,
        kind: "dmenu",
        icon: icon,
        iconFont: "",
        appIcon: "",
        appId: "",
        label: label,
        target: "",
        detail: detail,
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: i,
        section: ""
      })
    }

    layoutSerial += 1

    if (displayModel.count === 0)
      selectedIndex = 0
    else if (selectedIndex >= displayModel.count)
      selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0)
      selectedIndex = 0

    Qt.callLater(function () {
      if (displayModel.count > 0)
        root.revealCursor()
    })
  }

  // Refills displayModel with the active menu's visible children, or the ranked search hits.
  function rebuildDisplay(): void {
    if (root.dmenuActive) {
      root.rebuildDmenuDisplay()
      return
    }

    displayModel.clear()

    if (!root.rowsLoaded)
      return
    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var rows = []
    var query = root.filterText.trim()
    root.searchDivider = false

    if (query) {
      var currentRows = []
      var drilldownRows = []

      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root")
          continue
        if (!MenuModel.isDescendantOf(root.items, entry.id, active))
          continue
        if (!MenuModel.matchesQuery(entry, query, MenuModel.isVisible(root.items, root.itemOrder, guards.whenResults, entry)))
          continue
        var detail = MenuModel.parentPathFor(root.items, entry.id)
        var row = MenuModel.displayRow(root.items, root.itemOrder, guards.checkedResults, entry, detail, MenuModel.searchScore(root.items, entry, query))
        if (entry.parent === active)
          currentRows.push(row)
        else
          drilldownRows.push(row)
      }

      var searchSort = function (a, b) {
        if (a.score !== b.score)
          return a.score - b.score
        return a.path.localeCompare(b.path)
      }

      currentRows.sort(searchSort)
      drilldownRows.sort(searchSort)
      // Favorites and Recent hold copies of app rows: show each app once.
      rows = MenuModel.dedupeAppRows(currentRows.concat(drilldownRows))
      var drilldownIds = ({})
      for (var d = 0; d < drilldownRows.length; d++)
        drilldownIds[drilldownRows[d].itemId] = true
      var currentCount = 0
      for (var c = 0; c < rows.length; c++) {
        if (!drilldownIds[rows[c].itemId])
          currentCount += 1
      }
      root.searchDivider = currentCount > 0 && currentCount < rows.length
      if (root.searchDivider) {
        for (var e = 0; e < rows.length; e++) {
          if (drilldownIds[rows[e].itemId])
            rows[e].section = "drilldown"
        }
      }
    } else {
      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.parent !== active)
          continue
        if (!MenuModel.isVisible(root.items, root.itemOrder, guards.whenResults, child))
          continue
        rows.push(MenuModel.displayRow(root.items, root.itemOrder, guards.checkedResults, child, child.description, child.order))
      }

      // DesktopEntries can reorder its values when an application starts.
      // Keep the Apps menu alphabetical independently of provider refreshes,
      // with Favorites and Recent on top.
      if (active === "apps")
        rows = MenuModel.sortAppsMenu(rows)
    }

    for (var k = 0; k < rows.length; k++)
      displayModel.append(rows[k])
    layoutSerial += 1

    if (displayModel.count === 0)
      selectedIndex = 0
    else if (selectedIndex >= displayModel.count)
      selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0)
      selectedIndex = 0

    Qt.callLater(function () {
      if (displayModel.count > 0)
        root.revealCursor()
    })
  }

  // Moves the cursor by `delta` rows, wrapping; the first move activates the cursor.
  function select(delta: int): void {
    if (displayModel.count === 0)
      return
    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    revealCursor()
  }

  // Sets the search text, resets the cursor and rebuilds the rows.
  function setFilter(nextFilter: string): void {
    root.freezeCardTop()
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = root.mode !== "input"
    root.disarmPointer()
    if (!root.dmenuActive && root.filterText.trim())
      providers.loadForSearch(root.activeMenu)
    root.rebuildDisplay()
  }

  // Shows submenu `id` (root if unknown), optionally pushing the current one onto navStack.
  function setActiveMenu(id: string, pushHistory: bool, fromPointer: bool): void {
    root.freezeCardTop()
    if (!root.item(id))
      id = "root"
    if (pushHistory && id !== root.activeMenu)
      root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = id
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    if (fromPointer && root.view)
      root.view.allowInitialPointerSample()
    else if (!fromPointer)
      root.disarmPointer()
    root.rebuildDisplay()
    providers.invalidateVolatile(id)
    providers.load(id)
  }

  // Returns to the previous submenu (or the parent); returns false on root.
  function goBack(): bool {
    if (root.activeMenu === "root")
      return false

    if (root.navStack.length > 0) {
      var previous = root.navStack[root.navStack.length - 1]
      root.navStack = root.navStack.slice(0, root.navStack.length - 1)
      root.setActiveMenu(previous, false, false)
      return true
    }

    var active = root.item(root.activeMenu)
    root.setActiveMenu((active && active.parent) ? active.parent : "root", false, false)
    return true
  }

  // Activates row `index`: open a submenu, launch an app, run an action, or answer a dmenu request.
  function activateIndex(index: int, fromPointer: bool): void {
    if (history.deleteConfirmOpen)
      return
    if (root.dmenuActive) {
      if (root.mode === "input") {
        root.applyDmenuSelection(root.filterText)
        return
      }
      if (index < 0 || index >= displayModel.count)
        return
      var picked = displayModel.get(index)
      root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label)
      return
    }

    if (index < 0 || index >= displayModel.count)
      return
    var row = displayModel.get(index)
    if (row.kind === "menu" || row.kind === "link") {
      root.setActiveMenu(row.target || row.itemId, true, fromPointer)
    } else if (row.kind === "app") {
      var appId = row.appId
      var label = row.label
      root.recordRecentApp(appId)
      applySerial = requestSerial
      opened = false
      filterText = ""
      if (root.appLibrary)
        root.appLibrary.launch(appId, label)
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  // Asks to uninstall the app under the cursor (app rows only).
  function requestDeleteSelected(): void {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count)
      return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "app")
      return
    if (root.view)
      root.view.resetDeleteConfirm()
    history.requestDelete(row.appId, row.label)
  }

  // Dismisses the uninstall dialog and gives focus back to the menu.
  function cancelDelete(): void {
    history.cancelDelete()
    if (root.view)
      root.view.resetDeleteConfirm()
    root.disarmPointer()
    Qt.callLater(function () {
      root.focusKeys()
    })
  }

  // Closes the menu and uninstalls the app picked in the dialog.
  function confirmDelete(): void {
    var target = history.takeDeleteTarget()
    if (!target)
      return
    root.cancel()
    if (root.appLibrary)
      root.appLibrary.remove(target.appId, target.label)
  }

  // Closes the menu and answers the dmenu request with `value`.
  function applyDmenuSelection(value: string): void {
    applySerial = requestSerial
    opened = false
    filterText = ""
    root.finishRequest(value)
  }

  // Closes the menu and runs the selected action; an empty id just cancels.
  function applySelected(id, action) {
    if (!id) {
      cancel()
      return
    }

    applySerial = requestSerial
    opened = false
    filterText = ""
    root.runAction(action)
  }

  // Closes the menu, answering a dmenu request as cancelled.
  function cancel(): void {
    root.pendingInitialMenu = ""
    if (root.dmenuActive)
      root.finishRequest(null)
    opened = false
    filterText = ""
  }

  // Opens the menu at `initialMenu` (root if unknown) and starts its provider.
  function openExistingMenu(initialMenu) {
    requestSerial += 1
    mode = "menu"
    requestActive = false
    selectionFile = ""
    doneFile = ""
    activeMenu = root.item(initialMenu) ? initialMenu : "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = true
    root.disarmPointer()
    guards.evaluate(root.items)
    opened = true
    rebuildDisplay()
    providers.invalidateVolatile(activeMenu)
    providers.load(activeMenu)
    // The shell may start before first-install packages have finished placing
    // their icons. Refresh here even when the desktop entry list did not change.
    if (root.appLibrary)
      root.appLibrary.refreshIcons()

    Qt.callLater(function () {
      root.focusKeys()
    })
  }

  // Opens a dmenu select/input request from the payload's prompt, options and result files.
  function openDmenu(payload) {
    root.pendingInitialMenu = ""
    requestSerial += 1
    mode = payload.mode === "input" ? "input" : "select"
    dmenuPrompt = String(payload.prompt || (mode === "input" ? "Input" : "Select"))
    dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    selectionFile = String(payload.selectionFile || "")
    doneFile = String(payload.doneFile || "")
    requestActive = !!doneFile
    dmenuWidth = Math.max(1, Number(payload.width || 300))
    dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
    activeMenu = "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = mode !== "input"
    root.disarmPointer()
    opened = true
    rebuildDisplay()

    Qt.callLater(function () {
      root.focusKeys()
    })
  }
  ListModel {
    id: rowsModel
  }

  // ----------------------------------------------------------- route surface
  //
  // The menu is opened through the standard plugin lifecycle:
  // `omarchy-shell shell summon araneadev.menu '{"menu":"system"}'`.
  // Callers may pass a real id (`system`, `setup.power`) or an alias declared
  // in JSONC (`power`, `reminder-set`). Unknown strings fall through to the
  // id-as-route behavior so misspellings still attempt to open the literal id.
  function resolveRoute(input: string): string {
    return MenuModel.resolveRoute(root.items, root.itemOrder, input)
  }

  // Opens a route: runs an action alias directly, follows links, else opens that menu.
  function openRoute(initialMenu: string): void {
    // Favorites and Recent are injected by the Apps provider, so resolve
    // them after that provider has merged its generated submenu entries.
    if (initialMenu === "apps.favorites" || initialMenu === "apps.recent") {
      root.pendingInitialMenu = initialMenu
      providers.start("apps")
      root.resolvePendingAppsRoute()
      return
    }
    // Any other route replaces a Favorites/Recent route still waiting at startup.
    root.pendingInitialMenu = ""
    var id = root.resolveRoute(initialMenu)
    var entry = root.items[id]
    // If the resolved id is an action (i.e. the user invoked an alias for
    // a leaf, e.g. `omarchy-shell shell summon araneadev.menu '{"menu":"screenrecord-stop"}'`), run it directly
    // instead of opening an action with no children.
    if (entry && entry.kind === "action" && entry.action) {
      root.cancel()
      root.runAction(entry.action)
      return
    }
    // If it's a link (a redirect to another menu), follow the link.
    if (entry && entry.kind === "link" && entry.target)
      id = entry.target
    root.openExistingMenu(id)
  }

  // Opens a pending Favorites/Recent route once the menu sources are loaded
  // (a rebuild before that would drop the generated rows again): the route
  // when its rows exist, else Apps.
  function resolvePendingAppsRoute(): void {
    var route = root.pendingInitialMenu
    if (!route || !root.rowsLoaded || !root.menuSourcesReady)
      return
    root.pendingInitialMenu = ""
    root.openExistingMenu(root.item(route) ? route : "apps")
  }

  // Ignores the pointer until it actually moves, so a still mouse cannot steal the cursor.
  function disarmPointer() {
    if (root.view)
      root.view.disarmPointer()
  }

  // Moves the cursor to row `index` when the pointer has really moved over it.
  function selectFromPointer(index, item, mouse) {
    if (!root.view || !root.view.pointerMoved(item, mouse))
      return
    root.cursorActive = true
    root.selectedIndex = index
  }

  Process {
    id: resultProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      localAppLibrary.appsChanged()
    }
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (providers.loaded["apps"])
        root.loadApps()
    }
  }

  // Omarchy's default menu file and the user extension; a change rebuilds the items.
  MenuSources {
    id: sources
    omarchyPath: root.omarchyPath
    onUpdated: root.rebuildItemsFromSources()
  }
  // Omarchy's default menu file (tests point it at a fixture).
  property alias defaultMenuPath: sources.defaultMenuPath

  // Batched `when:` and `checked:` guards; a finished batch rebuilds the rows.
  MenuGuards {
    id: guards
    onUpdated: root.rebuildIfOpen()
  }

  // Rebuilds the rows when the menu is showing; children report changes here.
  function rebuildIfOpen(): void {
    if (root.opened)
      root.rebuildDisplay()
  }
}
