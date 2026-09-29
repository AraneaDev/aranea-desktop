// Aranea menu: the plugin's "menu" entry point (manifest.json), summoned by
// omarchy-shell. Renders the JSONC command menu with app launcher, providers
// and guards, and also serves dmenu-style select/input requests.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea
import "MenuModel.js" as MenuModel

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
  // Omarchy's default menu file has loaded (or is missing).
  property bool defaultMenuSeen: false
  // The user's menu extension file has loaded (or is missing).
  property bool userMenuSeen: false
  // Both menu files have reported: a pending route can only resolve then, or
  // it would resolve against a half-built menu and fall back to the root.
  readonly property bool menuSourcesReady: root.defaultMenuSeen && root.userMenuSeen
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
    if (root.deleteConfirmOpen) {
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
      root.activateTile(root.rootTiles[event.key - Qt.Key_1])
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
      root.fontFamily = payload.fontFamily

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
    defaultMenuFile.reload()
    userMenuFile.reload()
    return "ok"
  }

  // Liveness check: always returns "ok".
  function ping(): string {
    return "ok"
  }

  // Font for all menu text; a payload's fontFamily overrides it.
  property string fontFamily: Style.font.menuFamily
  // Directory of the current theme's branding marks (the header logo).
  readonly property string brandingMarksPath: Aranea.RuntimePaths.brandingMarksPath
  // Directory of the current theme's branding motifs (header art, dividers).
  readonly property string brandingMotifsPath: Aranea.RuntimePaths.brandingMotifsPath
  // Directory of the current theme's branding glyphs (status icons).
  readonly property string brandingGlyphsPath: Aranea.RuntimePaths.brandingGlyphsPath
  // JSONC menu definitions. The shell parses both at startup and merges
  // the user file on top of the defaults, so the keybind → IPC → visible
  // path doesn't have to shell out to bash + jq on every open.
  property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  // User extension file merged over the defaults.
  property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  // Items parsed from the default JSONC file.
  property var defaultMenuItems: []
  // Items parsed from the user JSONC file ([] when it is missing).
  property var userMenuItems: []
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
  // Menu ids whose bash provider is running (id → true).
  property var providerLoadingMenus: ({})
  // Menu ids whose last bash provider run exited nonzero (id → true).
  property var providerErrorMenus: ({})
  // What the empty list shows for the active menu (its own provider only).
  readonly property var emptyStateInfo: MenuModel.emptyState({
    loading: !!root.providerLoadingMenus[root.activeMenu],
    error: !!root.providerErrorMenus[root.activeMenu],
    filter: root.filterText
  })

  // Returns a copy of map with key set (or removed); maps are replaced, not mutated, so bindings update.
  function withFlag(map: var, key: string, value: bool): var {
    var next = ({})
    for (var k in map)
      next[k] = map[k]
    if (value)
      next[key] = true
    else
      delete next[key]
    return next
  }
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
  // Submenu ids whose provider has run (or started) since the last rebuild.
  property var providersLoaded: ({})
  // Submenu ids waiting for providerProc to become free.
  property var providerQueue: []
  // Bumped on each rebuild so output from an older provider run is discarded.
  property int providerRevision: 0
  // Maximum number of pinned apps kept.
  readonly property int favoriteAppLimit: 12
  // Maximum number of recent apps kept.
  readonly property int recentAppLimit: 12
  // Pinned app ids, saved to the state file.
  property var favoriteAppIds: []
  // Recently launched app ids, newest first, saved to the state file.
  property var recentAppIds: []
  // Last generated Apps rows, including the Favorites and Recent submenus.
  property var appRows: []
  // Aranea state directory ($XDG_STATE_HOME/aranea).
  readonly property string stateRoot: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/aranea"
  // Favourites and recents on disk, so they survive shell restarts.
  readonly property string appHistoryPath: root.stateRoot + "/menu.json"
  // One-off message that replaces the key hints until noticeTimer clears it.
  property string notice: ""

  // Loads the favourites and recents; a missing or broken file means none.
  FileView {
    id: appHistoryFile
    path: root.appHistoryPath
    // Load before anything can pin or launch, so the file never overwrites newer changes.
    blockLoading: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyAppHistory(text())
    onLoadFailed: root.applyAppHistory("")
  }

  // Makes sure the state directory exists before the first write.
  Process {
    running: true
    command: ["mkdir", "-p", root.stateRoot]
  }

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
  QtObject {
    id: localAppLibrary
    signal appsChanged

    function entryName(entry) {
      return String((entry && entry.name) || (entry && entry.id) || "")
    }
    function entrySubtext(entry) {
      return String((entry && entry.genericName) || "")
    }
    function sortedEntries(query) {
      var needle = String(query || "").trim().toLowerCase()
      var values = DesktopEntries.applications.values || []
      var rows = []
      for (var i = 0; i < values.length; i++) {
        var entry = values[i]
        if (!entry || entry.noDisplay || !entryName(entry))
          continue
        var text = [entryName(entry), entrySubtext(entry), entry.comment, entry.id].join(" ").toLowerCase()
        if (needle && text.indexOf(needle) < 0)
          continue
        rows.push({
          entry: entry,
          score: needle ? 1 : 0,
          key: entryName(entry).toLowerCase(),
          name: entryName(entry).toLowerCase()
        })
      }
      rows.sort(function (a, b) {
        return a.key < b.key ? -1 : (a.key > b.key ? 1 : 0)
      })
      return rows
    }
    function iconSource(icon) {
      var value = String(icon || "")
      if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0)
        return value
      if (value.charAt(0) === "/")
        return Util.fileUrl(value)
      return Quickshell.iconPath(value || "application-x-executable", true)
    }
    function refreshIcons() {
    }
    function launch(desktopId, name) {
      var id = String(desktopId || "")
      if (id)
        root.run("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
    }
    function remove(desktopId, name) {
      var id = String(desktopId || "")
      if (id)
        root.run(Util.shellQuote(root.omarchyPath + "/bin/omarchy-remove-launcher-entry") + " " + Util.shellQuote(id) + " " + Util.shellQuote(String(name || id)))
    }
  }
  // Whether the uninstall confirmation dialog is showing.
  property bool deleteConfirmOpen: false
  // App awaiting uninstall confirmation ({appId, label}), or null.
  property var deleteTarget: null
  onOpenedChanged: {
    if (!opened) {
      deleteConfirmOpen = false
      deleteTarget = null
      headerMarkSettled = false
    } else if (!motionEnabled) {
      headerMarkSettled = true
    } else {
      Qt.callLater(function () {
        headerMarkSettled = true
      })
    }
  }

  // Applies the state file's favourites and recents and regenerates the Apps rows.
  function applyAppHistory(raw: string): void {
    var history = MenuModel.parseAppHistory(raw, root.favoriteAppLimit, root.recentAppLimit)
    root.favoriteAppIds = history.favorites
    root.recentAppIds = history.recent
    root.mergeAppRows()
  }

  // Writes pinned and recent app ids to the state file.
  function saveAppHistory(): void {
    appHistoryFile.setText(MenuModel.serializeAppHistory(root.favoriteAppIds, root.recentAppIds, root.favoriteAppLimit, root.recentAppLimit))
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

  // Pins or unpins an app, saves, and regenerates the Apps rows; a 13th pin is refused with a notice.
  function toggleFavoriteApp(appId: string): void {
    var result = MenuModel.toggleFavoriteApp(root.favoriteAppIds, appId, root.favoriteAppLimit)
    if (result.refused) {
      root.showNotice("12 FAVOURITES · UNPIN ONE FIRST")
      return
    }
    root.favoriteAppIds = result.ids
    root.saveAppHistory()
    root.mergeAppRows()
  }

  // Moves an app to the front of Recent, saves, and regenerates the Apps rows.
  function recordRecentApp(appId: string): void {
    root.recentAppIds = MenuModel.recordRecentApp(root.recentAppIds, appId, root.recentAppLimit)
    root.saveAppHistory()
    root.mergeAppRows()
  }
  // Bound to the central [menu] section in shell.toml via Color.qml.
  // Each color already includes its alpha companion (composed in the
  // singleton), so consumers can drop them straight into a Rectangle.
  property color background: Color.menu.background
  // Menu text color.
  property color foreground: Color.menu.text
  // Card border color.
  property color border: Color.menu.border
  // Border spec for the card, from the shell's menu border settings.
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(1)))
  // Full-screen backdrop color behind the card.
  property color scrim: Color.menu.scrim
  // Keep the new ornamentation derived from the stable shell palette.  The
  // shell's menu parser intentionally exposes only the established surface
  // tokens, so these are composited here instead of reaching for ad-hoc
  // Color.menu members that older shells do not publish.
  property color contextText: Util.alpha(foreground, 0.58)
  // Root tile fill: tinted with the selection color when hovered.
  function hoveredTileBackground(hovered: bool): color {
    return hovered ? Util.alpha(selectedText, 0.10) : Util.alpha(foreground, 0.028)
  }
  // Color of the root footer text.
  property color footerText: Util.alpha(foreground, 0.58)
  // Opacity of the node-divider motif above the footer.
  property real nodeAlpha: 0.35
  // Background of the cursor row.
  property color selectedBackground: Color.menu.selectedBackground
  // Text color of the cursor row; also tints hovered tiles and the cursor bar.
  property color selectedText: Color.menu.selectedText
  // Border color of the cursor row.
  property color selectedBorder: Color.menu.selectedBorder
  // Border spec for the cursor row.
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  // Left border width of the cursor row, added to every row's content inset.
  readonly property real rowReservedBorderLeft: Border.left(selectedBorderSpec)
  // Space the row reserves on its right edge for the selection border.
  readonly property real rowReservedBorderRight: Border.right(selectedBorderSpec)
  // Corner radius of the card and its header.
  readonly property int cornerRadius: Math.max(8, Style.space(8))
  // Scale applied to shell font sizes by menuFontSize().
  readonly property real menuFontScale: 1.10
  // Letter spacing for menu labels.
  readonly property real menuLetterSpacing: 0.20
  // Scales a shell font size by menuFontScale, rounded, at least 1.
  function menuFontSize(size: real): int {
    return Math.max(1, Math.round(size * root.menuFontScale))
  }
  // Padding inside the card.
  property int contentMargin: Style.spacing.panelPadding
  // Header height for submenus and dmenu requests.
  property int headerHeight: Math.max(Style.space(46), root.menuFontSize(Style.font.title) + Style.spacing.controlPaddingY * 2)
  // Header height on the unfiltered root menu.
  property int rootHeaderHeight: Math.max(Style.space(68), root.menuFontSize(Style.font.title) + Style.spacing.controlPaddingY * 2)
  // Height of the root tile row.
  property int rootTileHeight: Style.space(96)
  // Height of the root context band (status, workspace, clock).
  property int rootContextHeight: Style.space(20)
  // Height of the root footer.
  property int footerHeight: Style.space(26)
  // Extra card height for the root context band, tiles and footer (0 elsewhere).
  property int rootExtrasHeight: root.fullRootHeader ? root.rootContextHeight + root.rootTileHeight + root.footerHeight + root.contentSpacing * 3 : 0
  // Keep the polished default, while allowing a session-wide reduced-motion
  // override for accessibility and deterministic testing.
  property bool motionEnabled: Aranea.MotionState.motionEnabled
  // Shared state file whose "off" content disables animations.
  readonly property string motionStatePath: Aranea.RuntimePaths.motionStatePath
  // Set a turn after opening so the root header mark can fade in.
  property bool headerMarkSettled: false
  // True on the unfiltered root menu, which shows the large header, tiles and footer.
  readonly property bool fullRootHeader: !root.dmenuActive && root.activeMenu === "root" && !root.filterText.trim()
  // Focused workspace label for the root context band.
  readonly property string workspaceContext: Hyprland.focusedWorkspace ? "WORKSPACE " + Hyprland.focusedWorkspace.id : "WORKSPACE —"
  // HH:mm time shown in the root context band; ticks every minute.
  readonly property string clockContext: Qt.formatDateTime(menuClock.date, "HH:mm")

  // Minute clock for clockContext.
  SystemClock {
    id: menuClock
    precision: SystemClock.Minutes
    enabled: root.opened
  }
  // Fixed tiles (Files, Terminal, Setup) shown on the root menu.
  readonly property var rootTiles: [({
        id: "tile.files",
        label: "Files",
        detail: "BROWSE  ·  ^1",
        icon: "󰉋",
        source: "fixed"
      }), ({
        id: "tile.terminal",
        label: "Terminal",
        detail: "EXECUTE  ·  ^2",
        icon: "",
        source: "fixed"
      }), ({
        id: "tile.setup",
        label: "Setup",
        detail: "CONFIGURE  ·  ^3",
        icon: "",
        source: "fixed"
      })]

  // Section spacing on the root menu; also used in the card height math.
  property int contentSpacing: Style.space(12)
  // Vertical spacing between card sections elsewhere.
  property int compactContentSpacing: Style.space(8)
  // Height of a row without a detail line.
  property int baseRowHeight: Math.max(Style.space(40), root.menuFontSize(Style.font.bodySmall) + Style.space(6) * 2)
  // Row-list height when nothing matches.
  property int emptyStateHeight: Style.space(112)
  // Height of a row that shows a detail line.
  property int detailRowHeight: Math.max(Style.space(58), root.menuFontSize(Style.font.bodySmall) + root.menuFontSize(Style.font.caption) + Style.space(7) * 2)
  // How much of the first hidden row stays visible at the fold — enough to
  // read as a cut-off row rather than a bottom border.
  property int rowPeek: Math.round(baseRowHeight * 0.55)
  // Gap between rows.
  property int rowSpacing: Style.space(4)
  // Height of the divider before drilldown search results.
  property int dividerHeight: Style.space(20)
  // Whether search results are split into current-menu and drilldown sections.
  property bool searchDivider: false
  // Bumped after each display rebuild so row-height bindings recompute.
  property int layoutSerial: 0
  // Card width: depends on mode and menu, capped to the screen.
  property int cardWidth: Math.min(root.dmenuActive ? Math.max(Style.space(root.dmenuWidth), Style.space(420)) : root.fullRootHeader ? Style.space(640) : ((root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "style.font") ? Style.space(560) : Style.space(480)), root.screenWidth - Style.gapsOut * 2)
  // Height given to the row list for the current rows.
  property int visibleRowsHeight: root.dmenuActive ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText) : rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)
  // Total card height, capped to the screen.
  property int cardHeight: root.dmenuActive ? Math.min(contentMargin * 2 + headerHeight + (mode === "input" ? 0 : contentSpacing + visibleRowsHeight), root.screenHeight - Style.gapsOut * 2) : Math.min(contentMargin * 2 + (root.fullRootHeader ? root.rootHeaderHeight : headerHeight) + contentSpacing + root.rootExtrasHeight + visibleRowsHeight, root.screenHeight - Style.gapsOut * 2)

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
    return (root.fullRootHeader || root.filterText || root.dmenuActive) && detail ? root.detailRowHeight : root.baseRowHeight
  }

  // Height the card can devote to rows before running off the screen — or
  // past the frozen top edge once a search has pinned the card in place.
  // Uses root.viewCardTop rather than effectiveCardTop: the centered top is
  // derived from the card height, which this value feeds.
  function availableRowsHeight(): int {
    var top = root.viewCardTop >= 0 ? root.viewCardTop : Style.gapsOut
    var headerHeight = root.fullRootHeader ? root.rootHeaderHeight : root.headerHeight
    var available = root.screenHeight - top - Style.gapsOut - root.contentMargin * 2 - headerHeight - root.contentSpacing - root.rootExtrasHeight
    // The starting menu sets the ceiling along with the offset: drilling into
    // a longer submenu scrolls behind the fold instead of growing the card.
    if (root.viewMaxRowsHeight >= 0)
      available = Math.min(available, root.viewMaxRowsHeight)
    // The root surface is intentionally a shorter command viewport: the
    // header, context band, tiles, and footer need to read as one composition
    // instead of allowing the command list to turn the card into a page.
    var menuCeiling = root.fullRootHeader ? Style.space(250) : Math.round(root.screenHeight * 0.7)
    return Math.min(available, menuCeiling)
  }

  // When every row fits, the list gets its full height. When they don't,
  // the card must end mid-row: a clipped row is what tells the eye there is
  // more below the fold, so never come out even on a row boundary.
  function foldedListHeight(totals: var, available: int): int {
    var count = totals.length
    if (count === 0)
      return root.baseRowHeight
    if (totals[count - 1] <= available)
      return totals[count - 1]

    var peek = root.rowPeek
    var full = 0
    while (full < count && totals[full] <= available)
      full++
    while (full > 1 && totals[full - 1] + root.rowSpacing + peek > available)
      full--
    if (full < 1)
      return Math.max(available, root.baseRowHeight)

    return totals[full - 1] + root.rowSpacing + peek
  }

  // Row-list height for the menu (arguments are unused; they only make the binding re-evaluate).
  function rowListHeight(_serial: int, _count: int, _filter: string, _divider: bool): int {
    if (displayModel.count === 0)
      return root.emptyStateHeight

    var totals = []
    var total = 0
    var previousSection = ""

    for (var i = 0; i < displayModel.count; i++) {
      var row = displayModel.get(i)
      if (i > 0)
        total += root.rowSpacing
      if (row.section === "drilldown" && previousSection !== "drilldown")
        total += root.dividerHeight
      total += root.rowHeightForDetail(row.detail)
      previousSection = row.section
      totals.push(total)
    }

    return foldedListHeight(totals, availableRowsHeight())
  }

  // Row-list height for a dmenu request (arguments only trigger re-evaluation).
  function dmenuRowListHeight(_serial: int, _count: int, _filter: string): int {
    if (root.mode === "input")
      return 0
    if (displayModel.count === 0)
      return root.baseRowHeight

    var available = availableRowsHeight()
    if (root.dmenuMaxHeight > 0)
      available = Math.min(available, Style.space(root.dmenuMaxHeight))

    var totals = []
    var total = 0
    for (var i = 0; i < displayModel.count; i++) {
      if (i > 0)
        total += root.rowSpacing
      total += root.rowHeightForDetail(displayModel.get(i).detail)
      totals.push(total)
    }

    return foldedListHeight(totals, available)
  }

  // Returns the item with this id, or null.
  function item(id: string): var {
    return root.items[id] || null
  }

  // ------------------------------------------------------------------
  // JSONC → normalized item array. Mirrors the bash bin's jq pipeline so
  // the on-disk authoring format stays untouched.
  // ------------------------------------------------------------------

  // Wrapper for MenuModel.stripJsonc.
  function stripJsonc(raw: string): string {
    return MenuModel.stripJsonc(raw)
  }

  // Wrapper for MenuModel.normalizeAliases.
  function normalizeAliases(value) {
    return MenuModel.normalizeAliases(value)
  }

  // Wrapper for MenuModel.normalizeItem.
  function normalizeItem(id: string, raw): var {
    return MenuModel.normalizeItem(id, raw)
  }

  // Wrapper for MenuModel.parseMenuJsonc.
  function parseMenuJsonc(raw: string): var {
    return MenuModel.parseMenuJsonc(raw)
  }

  // Merge defaults + user extension. Later entries override earlier ones
  // on a per-key basis (so the user can tweak label/icon/action without
  // re-declaring the whole row).
  function rebuildItemsFromSources(): void {
    var mergedMenu = MenuModel.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
    root.providerRevision += 1
    root.providersLoaded = ({})
    root.providerQueue = []
    root.providerLoadingMenus = ({})
    root.providerErrorMenus = ({})
    root.items = mergedMenu.items
    root.itemOrder = mergedMenu.itemOrder
    root.rowsLoaded = true
    root.evaluateGuards()
    // The generated Apps rows (apps, Favorites, Recent) are not in the JSONC
    // sources: merge them back, so a rebuild (the user menu file loading after
    // the default one) keeps an open generated menu instead of resetting to root.
    if (root.appRows.length > 0)
      root.startProviderForMenu("apps")
    if (root.opened) {
      root.rebuildDisplay()
      if (!root.dmenuActive) {
        if (root.filterText.trim())
          root.loadProvidersForSearch()
        else
          root.loadProviderForMenu(root.activeMenu)
      }
    }
    if (root.pendingInitialMenu) {
      root.startProviderForMenu("apps")
      root.resolvePendingAppsRoute()
    }
  }

  // Each known provider is a tiny bash one-liner that enumerates a list and
  // emits one tab-delimited row per item: `label\tvalue\tcurrent`. The shell
  // turns those into menu items children of `menuId`. A `volatile` provider
  // re-runs every time its submenu is entered, so a font installed since the
  // shell started shows up without restarting it.
  readonly property var providers: ({
      "fonts": {
        script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
        icon: "",
        volatile: true,
        actionFor: function (value) {
          return "omarchy-font-set " + Util.shellQuote(value)
        }
      },
      "power-profiles": {
        script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
        icon: "\udb81\udc0b",
        actionFor: function (value) {
          return "omarchy-powerprofiles-set autodetect " + Util.shellQuote(value)
        }
      }
    })

  // Wrapper for MenuModel.slugify.
  function slugify(value: string): string {
    return MenuModel.slugify(value)
  }

  // The apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries) instead of a bash enumeration, so they carry image
  // icons, launch feedback, and uninstall support like the launcher.
  function mergeAppRows() {
    if (!root.appLibrary)
      return
    var rows = root.appLibrary.sortedEntries("")
    // Uninstalled apps must not use up favourite or recent slots; an app
    // library that has not loaded yet (no rows) must not wipe the lists.
    var installed = rows.map(function (r) {
      return String(r.entry.id || "")
    })
    var favorites = MenuModel.pruneAppIds(root.favoriteAppIds, installed)
    var recent = MenuModel.pruneAppIds(root.recentAppIds, installed)
    if (rows.length > 0 && (favorites.length !== root.favoriteAppIds.length || recent.length !== root.recentAppIds.length)) {
      root.favoriteAppIds = favorites
      root.recentAppIds = recent
      root.saveAppHistory()
    }
    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId)
        continue
      var subtext = root.appLibrary.entrySubtext(entry)
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
        label: root.appLibrary.entryName(entry),
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
    var favoriteRows = MenuModel.appRowsForIds(appRows, root.favoriteAppIds, "apps.favorites", "apps.favorites")
    var recentRows = MenuModel.appRowsForIds(appRows, root.recentAppIds, "apps.recent", "apps.recent")
    // Keep both generated destinations present even when they are empty. This
    // gives direct routes and screenshots a deliberate empty state, and lets
    // the sections become useful immediately after the first pin or launch.
    appRows.unshift({
      id: "apps.favorites",
      parent: "apps",
      kind: "menu",
      icon: "",
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

    root.appRows = appRows
    var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened)
      root.rebuildDisplay()
    root.resolvePendingAppsRoute()
  }

  // Runs the provider of submenu `id` unless it already ran; apps merge inline, others start providerProc.
  function startProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id])
      return
    if (entry.provider === "apps") {
      root.providersLoaded[id] = true
      root.mergeAppRows()
      return
    }
    var spec = root.providers[entry.provider]
    if (!spec)
      return
    root.providersLoaded[id] = true
    root.providerLoadingMenus = root.withFlag(root.providerLoadingMenus, id, true)
    root.providerErrorMenus = root.withFlag(root.providerErrorMenus, id, false)
    providerProc.menuId = id
    providerProc.providerKey = entry.provider
    providerProc.revision = root.providerRevision
    providerProc.collected = ""
    providerProc.command = ["bash", "-lc", spec.script]
    providerProc.running = true
  }

  // Turns a provider's tab-separated output into action rows under `menuId` and swaps them in.
  function mergeProviderRows(rows, menuId, providerKey) {
    var spec = root.providers[providerKey]
    if (!spec)
      return
    var lines = String(rows || "").split("\n")
    var providerRows = []
    var takenIds = ({})
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line)
        continue
      var parts = line.split("\t")
      var label = parts[0] || ""
      var value = parts[1] || parts[0] || ""
      var current = parts[2] || ""
      if (!label)
        continue
      // Distinct values can slugify alike — Fira Code and Fira-Code both give
      // fira-code — and a repeated id is dropped, which would silently lose a
      // row from the list. Nudge it until it is the row's own.
      var rowId = menuId + "." + root.slugify(value)
      while (takenIds[rowId])
        rowId += "-"
      takenIds[rowId] = true

      providerRows.push({
        id: rowId,
        parent: menuId,
        kind: "action",
        icon: (value === current) ? "✓" : (spec.icon || ""),
        label: label,
        title: "",
        target: "",
        description: "",
        action: spec.actionFor(value),
        provider: "",
        aliases: [],
        when: "",
        checked: "",
        order: 0
      })
    }
    var merged = MenuModel.swapProviderRows(root.items, root.itemOrder, menuId, providerRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened)
      root.rebuildDisplay()
  }

  // Starts the next queued provider once providerProc is free.
  function startNextProvider(): void {
    if (providerProc.running)
      return
    while (root.providerQueue.length > 0) {
      var id = root.providerQueue.shift()
      var entry = root.item(id)
      if (!entry || !entry.provider || root.providersLoaded[id])
        continue
      root.startProviderForMenu(id)
      return
    }
  }

  // Entering a submenu is the one moment a volatile list is worth paying for
  // again: it may have been reshaped by the last pick from it. Search doesn't
  // invalidate, or every keystroke would restart the same enumeration.
  function invalidateVolatileProvider(id) {
    var entry = root.item(id)
    var spec = entry && entry.provider ? root.providers[entry.provider] : null
    if (spec && spec.volatile)
      root.providersLoaded[id] = false
  }

  // Loads submenu `id`'s provider, queueing it when providerProc is busy.
  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id])
      return

    // Native providers don't touch providerProc, so they never need to queue.
    if (entry.provider === "apps") {
      root.startProviderForMenu(id)
      return
    }

    if (providerProc.running) {
      if (root.providerQueue.indexOf(id) < 0)
        root.providerQueue = root.providerQueue.concat([id])
      return
    }

    root.startProviderForMenu(id)
  }

  // Loads every not-yet-run provider under the active menu so search can see its rows.
  function loadProvidersForSearch() {
    var active = root.item(root.activeMenu) ? root.activeMenu : "root"

    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id])
        continue
      if (active !== "root" && entry.id !== active && !root.isDescendantOf(entry.id, active))
        continue
      root.loadProviderForMenu(entry.id)
    }
  }

  // Wrapper for MenuModel.depthFor on the current items.
  function depthFor(id: string): int {
    return MenuModel.depthFor(root.items, id)
  }

  // Wrapper for MenuModel.pathFor on the current items.
  function pathFor(id: string): string {
    return MenuModel.pathFor(root.items, id)
  }

  // Wrapper for MenuModel.parentPathFor on the current items.
  function parentPathFor(id: string): string {
    return MenuModel.parentPathFor(root.items, id)
  }

  // Wrapper for MenuModel.isDescendantOf on the current items.
  function isDescendantOf(id: string, ancestorId: string): bool {
    return MenuModel.isDescendantOf(root.items, id, ancestorId)
  }

  // Wrapper for MenuModel.childCount on the current items.
  function childCount(id: string): int {
    return MenuModel.childCount(root.items, root.itemOrder, id)
  }

  // Guarded items are hidden when their `when:` evaluates false. Static
  // submenus are also hidden when none of their descendants are visible;
  // provider-backed menus stay visible because their rows load on demand.
  function isVisible(entry): bool {
    return MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry)
  }

  // Label with the ✓ marker baked in when `checked:` evaluated truthy.
  function labelFor(entry): string {
    return MenuModel.labelFor(entry, root.checkedResults)
  }

  // Wrapper for MenuModel.searchableToken.
  function searchableToken(value: string): string {
    return MenuModel.searchableToken(value)
  }

  // Wrapper for MenuModel.leafIdFor.
  function leafIdFor(id: string): string {
    return MenuModel.leafIdFor(id)
  }

  // Wrapper for MenuModel.nameSearchText.
  function nameSearchText(entry): string {
    return MenuModel.nameSearchText(entry)
  }

  // Wrapper for MenuModel.termInSearchWords.
  function termInSearchWords(term: string, text: string): bool {
    return MenuModel.termInSearchWords(term, text)
  }

  // Wrapper for MenuModel.descriptionTextMatches.
  function descriptionTextMatches(query: string, text: string): bool {
    return MenuModel.descriptionTextMatches(query, text)
  }

  // Whether a visible item matches the query (MenuModel.matchesQuery).
  function matchesQuery(entry, query: string): bool {
    return MenuModel.matchesQuery(entry, query, root.isVisible(entry))
  }

  // Sort score for a search hit (MenuModel.searchScore).
  function searchScore(entry, query: string): real {
    return MenuModel.searchScore(root.items, entry, query)
  }

  // Builds a displayModel row for an item (MenuModel.displayRow).
  function displayRow(entry, detail, score, section) {
    return MenuModel.displayRow(root.items, root.itemOrder, root.checkedResults, entry, detail, score, section)
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
        if (!root.isDescendantOf(entry.id, active))
          continue
        if (!root.matchesQuery(entry, query))
          continue
        var detail = root.parentPathFor(entry.id)
        var row = root.displayRow(entry, detail, root.searchScore(entry, query))
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
        if (!root.isVisible(child))
          continue
        rows.push(root.displayRow(child, child.description, child.order))
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
      root.loadProvidersForSearch()
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
    root.invalidateVolatileProvider(id)
    root.loadProviderForMenu(id)
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
    if (root.deleteConfirmOpen)
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
  function requestDeleteSelected() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count)
      return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "app")
      return
    root.deleteTarget = {
      appId: row.appId,
      label: row.label
    }
    if (root.view)
      root.view.resetDeleteConfirm()
    root.deleteConfirmOpen = true
  }

  // Dismisses the uninstall dialog and gives focus back to the menu.
  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    if (root.view)
      root.view.resetDeleteConfirm()
    root.disarmPointer()
    Qt.callLater(function () {
      root.focusKeys()
    })
  }

  // Closes the menu and uninstalls the app picked in the dialog.
  function confirmDelete() {
    var target = root.deleteTarget
    root.deleteConfirmOpen = false
    root.deleteTarget = null
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
    root.evaluateGuards()
    opened = true
    rebuildDisplay()
    invalidateVolatileProvider(activeMenu)
    loadProviderForMenu(activeMenu)
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
      root.startProviderForMenu("apps")
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
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    property int revision: 0
    stdout: SplitParser {
      onRead: function (data) {
        providerProc.collected += data + "\n"
      }
    }
    onExited: function (exitCode, exitStatus) {
      root.providerLoadingMenus = root.withFlag(root.providerLoadingMenus, providerProc.menuId, false)
      if (providerProc.revision === root.providerRevision) {
        root.providerErrorMenus = root.withFlag(root.providerErrorMenus, providerProc.menuId, exitCode !== 0)
        root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
        if (root.filterText.trim())
          root.loadProvidersForSearch()
      }
      root.startNextProvider()
    }
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
      if (root.providersLoaded["apps"])
        root.mergeAppRows()
    }
  }

  // The JSONC sources are watched so live edits to the default file (or the
  // user extension at ~/.config/omarchy/extensions/omarchy-menu.jsonc) take
  // effect without restarting the shell.
  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.defaultMenuItems = root.parseMenuJsonc(text())
      root.defaultMenuSeen = true
      root.rebuildItemsFromSources()
    }
    onLoadFailed: {
      root.defaultMenuSeen = true
      root.rebuildItemsFromSources()
    }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.userMenuItems = root.parseMenuJsonc(text())
      root.userMenuSeen = true
      root.rebuildItemsFromSources()
    }
    onLoadFailed: {
      root.userMenuItems = []
      root.userMenuSeen = true
      root.rebuildItemsFromSources()
    }
    onFileChanged: reload()
  }

  // ---------------------------------------------------------------- guards
  //
  // `when:` (visibility) and `checked:` (✓ marker) are bash expressions the
  // shell wasn't allowed to evaluate before the perf rewrite. Now the shell
  // batches them into one bash subprocess per (re)load so the open path
  // never has to wait on them.

  // Latest `when:` results by id (false hides the item).
  property var whenResults: ({})       // id → true|false (allow visibility)
  // Latest `checked:` results by id (true adds the check mark).
  property var checkedResults: ({})    // id → true|false (show ✓)
  // Set when an evaluation was requested while one was running; it reruns afterwards.
  property bool guardsPending: false

  // Runs every `when:` and `checked:` guard in one bash batch (deferred if one is in flight).
  function evaluateGuards() {
    // Process ignores a command change while it is running, and `collected`
    // belongs to the run in flight, so a second evaluation cannot overwrite
    // the first: it would throw away the lines already read and never start.
    // The surviving tail then lands as the whole answer, and every id lost
    // with it goes back to showing, since a `when:` only hides on an explicit
    // false. Wait for the run in flight and evaluate once it lands instead.
    if (guardProc.running) {
      root.guardsPending = true
      return
    }
    root.guardsPending = false

    var script = MenuModel.guardScript(root.items)
    if (!script) {
      root.whenResults = ({})
      root.checkedResults = ({})
      return
    }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function (data) {
        guardProc.collected += data + "\n"
      }
    }
    onExited: function (exitCode, exitStatus) {
      // A batch that was killed rather than finished has only told us about
      // the rows it reached, and a row whose `when:` went unanswered shows.
      // Keep the last complete set rather than let a half-read one through.
      // A signal leaves the exit code at 0, so the status is what tells us.
      if (exitCode !== 0 || exitStatus !== 0) {
        if (root.guardsPending)
          Qt.callLater(function () {
            root.evaluateGuards()
          })
        return
      }

      var nextWhen = ({})
      var nextChecked = ({})
      var lines = guardProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line)
          continue
        var colon = line.lastIndexOf(":")
        if (colon < 0)
          continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0)
          continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w")
          nextWhen[id] = value
        else if (tag === "c")
          nextChecked[id] = value
      }
      root.whenResults = nextWhen
      root.checkedResults = nextChecked
      if (root.opened)
        root.rebuildDisplay()
      // Run the evaluation that had to stand aside. Deferred by a turn so the
      // process is settled before its command is set again.
      if (root.guardsPending)
        Qt.callLater(function () {
          root.evaluateGuards()
        })
    }
  }
}
