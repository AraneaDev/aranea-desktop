// Aranea emoji picker: a clone of Omarchy's emoji overlay (omarchy.emojis)
// in the Aranea menu language, with a RECENT row and the selected emoji's
// name. Search and data are Omarchy's own (EmojiSearch.js, emojis.json);
// inserting still goes through omarchy-menu-emoji-insert.
// Loaded by the Omarchy shell as the "overlay" entry point of the
// araneadev.emojis plugin (manifest.json); the host calls open()/close() and
// reads `opened`.

import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea
import "EmojiSearch.js" as EmojiSearch
import "EmojiLogic.js" as EmojiLogic

Item {
  id: root

  // Omarchy install root (OMARCHY_PATH); the host also sets it on load. Used to
  // run bin/omarchy-menu-emoji-insert.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  // Host plugin-shell handle, injected by the Omarchy shell; dismiss() calls
  // its hide().
  property var shell: null
  // Whether to create the on-screen window; tests switch it off to run the
  // picker offscreen.
  property bool windowEnabled: true
  // The window, once created; null offscreen.
  property var view: null
  // Runs a detached command (argv); tests replace it with a recorder.
  property var run: function (argv) {
    Quickshell.execDetached(argv)
  }
  // Public manifest of this plugin, injected by the host; its id is what
  // dismiss() asks the shell to hide.
  property var manifest: null

  // Whether the overlay is showing; read by the host to know the open state.
  property bool opened: false
  // Current search text; empty shows every emoji plus the RECENT row.
  property string filterText: ""
  // Index of the selected cell in the filtered grid.
  property int selectedIndex: 0
  // Whether the cursor is on (false when nothing is selectable).
  property bool cursorActive: false
  // Whether the mint outline shows on the cursor: whenever Enter has a
  // target (from open, after typing; never with no results).
  readonly property bool outlineShown: root.cursorActive && (root.inRecents ? root.recents.length > 0 : displayModel.count > 0)
  // When the cells last changed under a still pointer (Date.now()), 0 for
  // never: the picker opening, the shown emojis changing or the RECENT row
  // showing or hiding. Pointer clicks within 300 ms of it are refused unless
  // the pointer really moved onto the cell (ClickSettle).
  property real layoutChangedAt: 0
  // The shown emojis joined, so an equal rebuild does not stamp the layout.
  property string displayKeys: ""
  // The cursor is either in the RECENT row or in the grid.
  property bool inRecents: false
  // Index of the selected emoji in the RECENT row, used while inRecents.
  property int recentIndex: 0
  // All entries parsed from emojis.json ({ e, k } objects).
  property var emojis: []
  // Entries matching filterText, in grid order.
  property var filteredEmojis: []
  // Keyword string by emoji, built from emojis; used to name the selection.
  property var keywordsByEmoji: ({})
  // Recently used emojis, newest first, loaded from and saved to recentsPath.
  property var recents: []

  // Aranea state directory: $XDG_STATE_HOME/aranea (default ~/.local/state/aranea).
  readonly property string stateRoot: Aranea.RuntimePaths.araneaStateRoot
  // File that stores the recent list (emoji-recent.json under stateRoot).
  readonly property string recentsPath: Aranea.RuntimePaths.emojiRecentsPath
  // The RECENT row shows only with an empty search and at least one recent.
  readonly property bool showRecents: !root.filterText && root.recents.length > 0

  // Card fill colour (menu background).
  property color background: Color.menu.background
  // Text colour for glyphs, labels and hints (menu text).
  property color foreground: Color.menu.text
  // Card border colour; feeds borderSpec.
  property color border: Color.menu.border
  // Border description handed to the card, from the menu surface style.
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Aranea.DesignTokens.borderWidth)
  // Colour of the full-screen backdrop behind the card.
  property color scrim: Color.menu.scrim
  // Fill of the selected cell.
  property color selectedBackground: Color.menu.selectedBackground
  // Accent colour: selected-cell ring, section labels and chrome accent.
  property color selectedText: Color.menu.selectedText
  // Corner radius of the card and of each cell.
  readonly property int cornerRadius: Aranea.DesignTokens.cornerRadius
  // Font for all text in the picker (menu family).
  property string fontFamily: Style.font.menuFamily
  // Inner padding of the card.
  property int contentMargin: Style.spacing.panelPadding
  // Card width: 440 scaled units, capped to the window minus outer gaps.
  property int cardWidth: root.view ? Math.min(Style.space(440), root.view.width - Style.gapsOut * 2) : Style.space(440)
  // Card height: 560 scaled units, capped to the window minus outer gaps.
  property int cardHeight: root.view ? Math.min(Style.space(560), root.view.height - Style.gapsOut * 2) : Style.space(560)

  // Width of one emoji cell (at least 44 scaled units, or the display font plus spacing).
  property int cellWidth: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  // Height of one emoji cell, sized like cellWidth.
  property int cellHeight: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  // From the real grid width (inside the chrome insets and the card border),
  // so Up/Down move straight rather than drifting diagonally.
  property int columns: Math.max(1, Math.floor((root.cardWidth - root.contentMargin * 2 - Border.left(root.borderSpec) - Border.right(root.borderSpec)) / root.cellWidth))

  // The emoji under the cursor, from the RECENT row or the grid; "" when none.
  readonly property string selectedEmoji: {
    if (root.inRecents)
      return root.recents[root.recentIndex] || ""
    var item = root.filteredEmojis[root.selectedIndex]
    return item ? item.e : ""
  }
  // Display name of selectedEmoji, derived from its keywords (EmojiLogic.emojiName).
  readonly property string selectedName: root.selectedEmoji ? EmojiLogic.emojiName(EmojiLogic.keywordsFor(root.keywordsByEmoji, root.selectedEmoji)) : ""

  // Shows the overlay with an empty search, the cursor in the RECENT row when
  // there are recents, and focuses the key handler. Called by the host; the
  // payload is ignored.
  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.recentIndex = 0
    root.inRecents = root.recents.length > 0
    root.cursorActive = true
    root.rebuildDisplay()
    if (root.view)
      root.view.disarmPointer()
    Qt.callLater(function () {
      if (root.view)
        root.view.focusKeys()
    })
  }

  // Opening the picker or showing/hiding the RECENT row moves the cells
  // under a still pointer.
  onOpenedChanged: if (root.opened)
    root.noteLayoutChange()
  onShowRecentsChanged: root.noteLayoutChange()

  // Stamps layoutChangedAt: the cells moved or changed under the pointer.
  function noteLayoutChange(): void {
    root.layoutChangedAt = Date.now()
  }

  // Scrolls grid cell INDEX into view (no-op offscreen).
  function reveal(index: int): void {
    if (root.view)
      root.view.reveal(index)
  }

  // Height of the result grid, for page moves (one row offscreen).
  function resultHeight(): real {
    return root.view ? root.view.resultHeight : root.cellHeight
  }

  // Hides the overlay without notifying the host shell.
  function close() {
    root.opened = false
  }

  // Hides the overlay and asks the host shell to hide this plugin.
  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "araneadev.emojis")
  }

  // Dismisses the overlay when open, otherwise opens it with an empty payload.
  function toggle() {
    if (root.opened)
      root.dismiss()
    else
      root.open("{}")
  }

  // Parses the emojis.json text into emojis and keywordsByEmoji, and refreshes
  // the grid when open.
  function loadEmojis(raw) {
    root.emojis = EmojiSearch.parseEmojis(raw)
    var map = {}
    for (var i = 0; i < root.emojis.length; i++)
      map[root.emojis[i].e] = root.emojis[i].k
    root.keywordsByEmoji = map
    if (root.opened)
      root.rebuildDisplay()
  }

  // Replaces the grid's cells with ROWS in place: cells that stay keep
  // their delegates (set), so a rebuild never recreates cells under the
  // pointer.
  function syncRows(rows: var): void {
    var keep = Math.min(displayModel.count, rows.length)
    for (var i = 0; i < keep; i++)
      displayModel.set(i, rows[i])
    if (displayModel.count > rows.length)
      displayModel.remove(rows.length, displayModel.count - rows.length)
    for (var j = keep; j < rows.length; j++)
      displayModel.append(rows[j])
  }

  // Re-runs the search over all emojis, refills the grid model in place,
  // stamps the layout when the shown emojis changed, clamps the selection
  // and leaves the RECENT row when it is hidden.
  function rebuildDisplay() {
    // No cap below the data size, so the count and the grid cover every emoji.
    var out = EmojiSearch.filterEmojis(root.emojis, root.filterText, Math.max(1000, root.emojis.length))
    root.filteredEmojis = out

    var rows = []
    var keys = []
    for (var j = 0; j < out.length; j++) {
      keys.push(out[j].e)
      rows.push({
        emoji: out[j].e,
        index: j
      })
    }
    root.syncRows(rows)
    var joined = keys.join("\n")
    if (joined !== root.displayKeys) {
      root.displayKeys = joined
      root.noteLayoutChange()
    }

    if (displayModel.count === 0)
      selectedIndex = 0
    else if (selectedIndex >= displayModel.count)
      selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0)
      selectedIndex = 0
    if (!root.showRecents)
      root.inRecents = false
    cursorActive = displayModel.count > 0 || root.inRecents

    Qt.callLater(function () {
      if (displayModel.count > 0 && !root.inRecents)
        root.reveal(root.selectedIndex)
    })
  }

  // Moves the cursor by delta cells, wrapping, within the RECENT row or the
  // grid; the outline is already on Enter's target, so the first move moves
  // it straight away.
  function select(delta) {
    if (root.inRecents) {
      root.recentIndex = (root.recentIndex + delta + root.recents.length) % root.recents.length
      return
    }
    if (displayModel.count === 0)
      return
    cursorActive = true
    selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    root.reveal(selectedIndex)
  }

  // Moves the cursor by delta rows, crossing between the RECENT row and the
  // grid at the same column; clamps at the ends of the grid.
  function selectRow(delta) {
    if (root.inRecents) {
      var count = root.recents.length
      var row = Math.floor(root.recentIndex / columns)
      var lastRow = Math.floor((count - 1) / columns)
      var column = root.recentIndex % columns
      if (delta > 0 && row >= lastRow) {
        // Down out of the last recent row enters the grid at the same column.
        if (displayModel.count === 0)
          return
        root.inRecents = false
        root.selectedIndex = Math.min(column, displayModel.count - 1)
        root.reveal(root.selectedIndex)
      } else if (delta > 0) {
        root.recentIndex = Math.min(root.recentIndex + columns, count - 1)
      } else if (row > 0) {
        root.recentIndex = root.recentIndex - columns
      }
      return
    }
    if (displayModel.count === 0)
      return
    cursorActive = true
    var newIndex = selectedIndex + delta * columns
    if (newIndex < 0) {
      // Up out of the first grid row enters the last recent row.
      if (root.showRecents) {
        var lastRowStart = Math.floor((root.recents.length - 1) / columns) * columns
        root.inRecents = true
        root.recentIndex = Math.min(lastRowStart + selectedIndex % columns, root.recents.length - 1)
        return
      }
      newIndex = 0
    }
    if (newIndex >= displayModel.count)
      newIndex = displayModel.count - 1
    selectedIndex = newIndex
    root.reveal(selectedIndex)
  }

  // Moves the grid cursor by delta pages (the rows visible in the grid),
  // clamped; does nothing in the RECENT row.
  function selectPage(delta) {
    if (root.inRecents || displayModel.count === 0)
      return
    var visibleRows = Math.max(1, Math.floor(root.resultHeight() / cellHeight))
    var newIndex = selectedIndex + delta * columns * visibleRows
    if (newIndex < 0)
      newIndex = 0
    if (newIndex >= displayModel.count)
      newIndex = displayModel.count - 1
    selectedIndex = newIndex
    root.reveal(selectedIndex)
  }

  // Sets the search text, resets the cursor to the first grid cell and
  // rebuilds the grid.
  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.inRecents = false
    root.cursorActive = true
    root.rebuildDisplay()
  }

  // Moves emoji to the front of the recent list (max 16) and writes it to
  // recentsPath.
  function remember(emoji) {
    root.recents = EmojiLogic.pushRecent(root.recents, emoji, 16)
    recentsFile.setText(EmojiLogic.serializeRecents(root.recents))
  }

  // Enter inserts into the focused window (Omarchy's command); Shift+Enter
  // only copies it.
  function applySelected(emoji, copyOnly) {
    if (!emoji)
      return
    root.remember(emoji)
    root.dismiss()
    if (copyOnly)
      root.run(["wl-copy", "--", emoji])
    else
      root.run([root.omarchyPath + "/bin/omarchy-menu-emoji-insert", emoji])
  }

  // A pointer click on grid cell INDEX, pressed while it held KEY (its
  // emoji): moves the cursor there and inserts it. Refused (false) when the
  // cell no longer holds KEY, so a click never lands on an emoji that
  // changed between press and release. Hover never moves the cursor.
  function activateKey(index: int, key: string): bool {
    if (!key || index < 0 || index >= displayModel.count || displayModel.get(index).emoji !== key)
      return false
    root.inRecents = false
    root.cursorActive = true
    root.selectedIndex = index
    root.applySelected(key, false)
    return true
  }

  // A pointer click on RECENT cell INDEX, pressed while it held KEY: inserts
  // it, or is refused (false) when the cell no longer holds KEY.
  function activateRecentKey(index: int, key: string): bool {
    if (!key || !root.showRecents || root.recents[index] !== key)
      return false
    root.inRecents = true
    root.cursorActive = true
    root.recentIndex = index
    root.applySelected(key, false)
    return true
  }

  // Handles a key press in the picker: Esc clears the search, then closes;
  // arrows and PageUp/PageDown move the cursor; Enter inserts the outlined
  // emoji (Shift copies; nothing with no results); other text edits the
  // search. Returns whether the key was handled.
  function handleKey(event: var): bool {
    if (event.key === Qt.Key_Escape) {
      if (root.filterText)
        root.setFilter("")
      else
        root.dismiss()
      return true
    } else if (Util.editsFilter(event, root.filterText)) {
      root.setFilter(Util.editedFilter(event, root.filterText))
      return true
    } else if (event.key === Qt.Key_Left) {
      root.select(-1)
      return true
    } else if (event.key === Qt.Key_Right) {
      root.select(1)
      return true
    } else if (event.key === Qt.Key_Up) {
      root.selectRow(-1)
      return true
    } else if (event.key === Qt.Key_Down) {
      root.selectRow(1)
      return true
    } else if (event.key === Qt.Key_PageUp) {
      root.selectPage(-1)
      return true
    } else if (event.key === Qt.Key_PageDown) {
      root.selectPage(1)
      return true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      // Enter acts on the outlined emoji; with no results it does nothing.
      if (root.outlineShown)
        root.applySelected(root.selectedEmoji, (event.modifiers & Qt.ShiftModifier) !== 0)
      return true
    } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
      root.setFilter(root.filterText + event.text)
      return true
    }
    return false
  }

  // Key hints for the chrome footer; Esc reads CLEAR while searching, else CLOSE.
  function hintText() {
    return ["←↑↓→ MOVE", "ENTER INSERT", "⇧ENTER COPY", "ESC " + (root.filterText ? "CLEAR" : "CLOSE")].join("  ·  ")
  }

  // Menu-like entrance (fade + slight scale), unless Aranea motion is off
  // (shared Aranea.MotionState).
  property bool motionEnabled: Aranea.MotionState.motionEnabled

  ListModel {
    id: rowsModel
  }
  // The grid's cells (the shown emojis), read by the window.
  readonly property alias displayModel: rowsModel

  FileView {
    path: String(Qt.resolvedUrl("emojis.json")).replace(/^file:\/\//, "")
    onLoaded: root.loadEmojis(text())
  }

  FileView {
    id: recentsFile
    path: root.recentsPath
    atomicWrites: true
    printErrors: false
    onLoaded: root.recents = EmojiLogic.parseRecents(text())
    onLoadFailed: root.recents = []
  }

  Process {
    running: true
    command: ["mkdir", "-p", root.stateRoot]
  }

  Component.onCompleted: {
    if (root.windowEnabled) {
      var windowComponent = Qt.createComponent(Qt.resolvedUrl("EmojiWindow.qml"))
      if (windowComponent.status === Component.Ready)
        root.view = windowComponent.createObject(root, {
          root: root
        })
      else
        console.warn("emojis: window failed to load:", windowComponent.errorString())
    }
  }
}
