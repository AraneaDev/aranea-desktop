// Aranea clipboard: a clone of Omarchy's clipboard picker (omarchy.clipboard)
// in the Aranea menu language, with typed rows, pins and masked, expiring
// secrets. Capture, paste and copy still use Omarchy's scripts; rules live in
// ClipboardLogic.js.
// Overlay entry point of the araneadev.clipboard plugin (manifest.json); the
// Omarchy shell keeps it loaded and calls open()/close()/toggle() on summon
// and hide. It records clipboard history in the background even while closed.

import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea
import "ClipboardLogic.js" as ClipboardLogic

Item {
  id: root

  // Omarchy install root ($OMARCHY_PATH), for its clipboard scripts.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  // Whether the picker window is shown.
  property bool opened: false
  // Current search text typed into the picker.
  property string filterText: ""
  // Cursor position in the displayed rows (display index, not history index):
  // the row Enter acts on. Only the keyboard (and a click) moves it.
  property int selectedIndex: 0
  // Whether the cursor is on; keys that act on a row need it.
  property bool cursorActive: false
  // Whether the mint outline shows on selectedIndex: whenever Enter has a
  // target (from open, after typing; never in the empty state).
  readonly property bool outlineShown: root.cursorActive && rowsModel.count > 0
  // When the rows last changed under a still pointer (Date.now()), 0 for
  // never: the picker opening or the shown entry ids changing. Pointer
  // clicks within 300 ms of it are refused unless the pointer really moved
  // onto the row (ClickSettle).
  property real layoutChangedAt: 0
  // The shown entry ids joined, so an equal rebuild does not stamp the layout.
  property string displayKeys: ""
  // Whether the "clear history" confirmation dialog is open.
  property bool clearConfirmOpen: false
  // All history entries (ClipboardLogic entries), newest first, as saved to historyPath.
  property var history: []
  // The rows shown in the picker (display order), read by the window.
  readonly property alias displayModel: rowsModel
  // Whether to create the on-screen window (ClipboardWindow.qml); tests
  // switch it off to run the picker offscreen.
  property bool windowEnabled: true
  // Whether to record the clipboard (wl-paste watchers); tests switch it off.
  property bool captureEnabled: true
  // The window, once created; null offscreen.
  property var view: null
  // Runs a detached command (argv); tests replace it with a recorder.
  property var run: function (argv) {
    Quickshell.execDetached(argv)
  }

  // Gives the window's key handler the keyboard focus (no-op offscreen).
  function focusKeys(): void {
    if (root.view)
      root.view.focusKeys()
  }

  // Scrolls the row at index into view (no-op offscreen).
  function reveal(index: int): void {
    if (root.view)
      root.view.reveal(index)
  }

  // History file shared with the stock Omarchy picker.
  property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  // Omarchy's capture script; wl-paste runs it on every copy and it prints the entry as JSON.
  property string captureScript: root.omarchyPath + "/shell/plugins/clipboard/capture.sh"
  // Shares the [menu] surface tokens; themes that style the menu also
  // style the clipboard. Selected-row colors composed in the
  // singleton so consumers drop them straight into Rectangle bindings.
  property color background: Color.menu.background
  // Text colour (menu text token).
  property color foreground: Color.menu.text
  // Border colour (menu border token); also tints the preview divider.
  property color border: Color.menu.border
  // Border description for the card, from the theme's [menu] border settings.
  property var borderSpec: Aranea.PanelChrome.surfaceBorder("menu", "border", border, Aranea.DesignTokens.borderWidth, true)
  // Colour laid over the screen behind the card.
  property color scrim: Color.menu.scrim
  // Background of the row under the cursor.
  property color selectedBackground: Color.menu.selectedBackground
  // Text colour of the row under the cursor; also the accent of the chrome.
  property color selectedText: Color.menu.selectedText
  // Corner radius of the card and rows.
  readonly property int cornerRadius: Aranea.DesignTokens.cornerRadius
  // Font for all picker text (the menu font).
  property string fontFamily: Aranea.Typography.uiFamily
  // Inner padding of the card and the preview pane.
  property int contentMargin: Style.spacing.panelPadding
  // Height of one history row (title plus detail line).
  property int rowHeight: Math.max(Style.space(50), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  // Unpinned entries kept in history; pinned ones do not count.
  property int historyLimit: 300
  // Secrets leave history this long after capture (pinned ones stay).
  readonly property real secretTtlMs: Number(Quickshell.env("ARANEA_CLIPBOARD_SECRET_TTL_MS")) || 600000
  // Clock for the remaining-time text; set on open and by the expiry timer.
  property real nowMs: Date.now()
  // Display index whose secret is revealed in the preview; any cursor move
  // masks it again.
  property int revealedIndex: -1
  // One-off message that replaces the key hints until noticeTimer clears it.
  property string notice: ""
  // Number of pinned entries, shown in the header counts.
  readonly property int pinnedCount: root.history.filter(function (e) {
    return e && e.pinned
  }).length
  onSelectedIndexChanged: root.revealedIndex = -1

  // Shows the picker with an empty filter and the cursor on the first row,
  // and focuses the key handler. Called by the shell on summon; the payload
  // is ignored.
  function open(payloadJson) {
    root.opened = true
    root.notice = ""
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.nowMs = Date.now()
    root.expireNow()
    root.rebuildDisplay()
    Qt.callLater(function () {
      root.focusKeys()
    })
  }

  // Opening the picker moves the rows under a still pointer.
  onOpenedChanged: if (root.opened)
    root.noteLayoutChange()

  // Stamps layoutChangedAt: the rows moved or changed under the pointer.
  function noteLayoutChange(): void {
    root.layoutChangedAt = Date.now()
  }

  // Hides the picker and dismisses the clear confirmation.
  function close() {
    root.notice = ""
    root.cancelClearHistory()
    root.opened = false
  }

  // Shows text on the hint line for three seconds.
  function showNotice(text) {
    root.notice = text
    noticeTimer.restart()
  }

  // Closes the picker when open, opens it otherwise.
  function toggle() {
    if (root.opened)
      root.close()
    else
      root.open("{}")
  }

  // Replaces the history with the parsed file contents, saves once when
  // entries needed a capture time, and expires old secrets.
  function loadHistory(raw) {
    root.history = ClipboardLogic.parseHistory(raw, Date.now())
    // Stock-written entries just got their capture time; keep it, so secret
    // expiry counts from the first load rather than from every restart.
    if (ClipboardLogic.hadUnstamped(raw))
      root.saveHistory()
    root.expireNow()
    if (root.opened)
      root.rebuildDisplay()
  }

  // Drops unpinned secrets older than secretTtlMs; saves and redraws only when something was dropped.
  function expireNow() {
    var result = ClipboardLogic.expire(root.history, Date.now(), root.secretTtlMs)
    if (!result.changed)
      return
    root.history = result.history
    root.saveHistory()
    if (root.opened)
      root.rebuildDisplay()
  }

  // Sets the history to next, saves it and redraws the list.
  function updateHistory(next) {
    root.history = next
    root.saveHistory()
    root.rebuildDisplay()
  }

  // Pins or unpins the entry shown at display index.
  function togglePinnedIndex(index) {
    if (index < 0 || index >= displayModel.count)
      return
    root.updateHistory(ClipboardLogic.togglePinned(root.history, displayModel.get(index).historyIndex, Date.now()))
  }

  // Marks the entry shown at display index as secret or not secret.
  function toggleSecretIndex(index) {
    if (index < 0 || index >= displayModel.count)
      return
    root.updateHistory(ClipboardLogic.toggleSecret(root.history, displayModel.get(index).historyIndex, Date.now()))
  }

  // Toggles showing the secret at display index in the preview; no-op for non-secret rows.
  function revealIndex(index) {
    if (index < 0 || index >= displayModel.count || !displayModel.get(index).secret)
      return
    root.revealedIndex = root.revealedIndex === index ? -1 : index
  }

  // Our own writes come back through watchChanges; skipping those echoes
  // avoids re-parsing the whole history, and skipping every reload while a
  // write is pending keeps an older file from replacing newer history.
  property var savedTexts: []
  // History writes started and not yet finished (saved or failed).
  property int pendingSaves: 0
  // Paste/copy/open actions waiting until no history write is pending; they
  // read the history file by index, so they must see the final file.
  property var pendingActions: []

  // Writes the history as pretty JSON to historyPath and counts the write as pending.
  function saveHistory() {
    var text = JSON.stringify(root.history, null, 2) + "\n"
    root.savedTexts = root.savedTexts.concat([text]).slice(-8)
    root.pendingSaves += 1
    saveWatchdog.restart()
    historyFile.setText(text)
  }

  // Counts one write as finished; when none is pending, runs the queued actions in order.
  function finishSave() {
    root.pendingSaves = Math.max(0, root.pendingSaves - 1)
    if (root.pendingSaves > 0)
      return
    saveWatchdog.stop()
    var actions = root.pendingActions
    root.pendingActions = []
    for (var i = 0; i < actions.length; i++)
      actions[i]()
  }

  // Runs action now, or queues it until every pending history write is done.
  function whenSaved(action) {
    if (root.pendingSaves > 0)
      root.pendingActions = root.pendingActions.concat([action])
    else
      action()
  }

  // Adds a captured entry to the top of history, saves and redraws when open.
  function addClipboardEntry(entry) {
    if (!entry)
      return
    root.history = ClipboardLogic.addEntry(root.history, entry, root.historyLimit, Date.now())
    root.saveHistory()
    if (root.opened)
      root.rebuildDisplay()
  }

  // Adds an entry from one JSON line printed by the capture script.
  function addClipboardJson(line) {
    root.addClipboardEntry(ClipboardLogic.parseEntryJson(line))
  }

  // Opens the clear confirmation (with "cancel" preselected) when history is not empty.
  function requestClearHistory() {
    if (root.history.length === 0)
      return
    if (root.view)
      root.view.resetClearConfirm()
    root.clearConfirmOpen = true
  }

  // Closes the clear confirmation and returns focus to the key handler.
  function cancelClearHistory() {
    root.clearConfirmOpen = false
    root.disarmPointer()
    Qt.callLater(function () {
      root.focusKeys()
    })
  }

  // Removes every unpinned entry, saves, and resets the cursor.
  function confirmClearHistory() {
    // Pinned items are kept: clearing is for the churn, not what was chosen.
    root.history = ClipboardLogic.clearUnpinned(root.history)
    root.saveHistory()
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.clearConfirmOpen = false
    root.rebuildDisplay()
    Qt.callLater(function () {
      root.focusKeys()
    })
  }

  // Deletes the entry shown at display index from history and keeps the cursor in range.
  function removeDisplayIndex(index) {
    if (index < 0 || index >= displayModel.count)
      return
    var row = displayModel.get(index)
    root.history = ClipboardLogic.removeEntryAt(root.history, row.historyIndex)
    root.saveHistory()

    if (displayModel.count <= 1) {
      root.selectedIndex = 0
    } else if (root.selectedIndex >= displayModel.count - 1) {
      root.selectedIndex = displayModel.count - 2
    }

    root.disarmPointer()
    root.rebuildDisplay()
  }

  // Replaces the shown rows with ROWS in place: rows that stay keep their
  // delegates (set), so a rebuild never recreates rows under the pointer.
  function syncRows(rows: var): void {
    var keep = Math.min(displayModel.count, rows.length)
    for (var i = 0; i < keep; i++)
      displayModel.set(i, rows[i])
    if (displayModel.count > rows.length)
      displayModel.remove(rows.length, displayModel.count - rows.length)
    for (var j = keep; j < rows.length; j++)
      displayModel.append(rows[j])
  }

  // Rebuilds the list model from history and the filter (at most 50 recent
  // rows plus pinned ones) in place, stamps the layout when the shown
  // entries changed, clamps the cursor and scrolls it into view.
  function rebuildDisplay() {
    root.revealedIndex = -1
    // list changed: rows may have moved under the cursor
    var rows = ClipboardLogic.displayRows(root.history, root.filterText, 50, Date.now())

    var items = []
    var keys = []
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      keys.push(row.entryId)
      items.push({
        entryId: row.entryId,
        section: row.section,
        kind: row.kind,
        secret: row.secret,
        pinned: row.pinned,
        title: row.title,
        detail: row.detail,
        entryType: row.kind === "image" ? "image" : "text",
        fullText: row.fullText,
        previewImage: row.previewImage ? Util.fileUrl(row.previewImage) : "",
        colour: row.colour,
        swatch: row.swatch,
        path: row.path,
        mime: row.mime,
        historyIndex: row.historyIndex
      })
    }
    root.syncRows(items)
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

    Qt.callLater(function () {
      if (displayModel.count > 0)
        root.reveal(root.selectedIndex)
    })
  }

  // Moves the cursor by delta rows, wrapping around; the outline is already
  // on Enter's target, so the first move moves it straight away.
  function select(delta) {
    if (displayModel.count === 0)
      return
    root.disarmPointer()
    root.cursorActive = true
    selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    root.reveal(selectedIndex)
  }

  // Puts the cursor on index, clamped to the list, and scrolls to it.
  function selectAbsolute(index) {
    if (displayModel.count === 0)
      return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    root.reveal(root.selectedIndex)
  }

  // Sets the search text, resets the cursor to the top and rebuilds the list.
  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  // Makes the mouse ignore hover until it really moves, so a still pointer does not steal the cursor.
  function disarmPointer() {
    if (root.view)
      root.view.disarmPointer()
  }

  // Handles a key press in the picker (the window forwards every key while
  // the clear confirmation is closed): Esc clears the search, then closes;
  // arrows, PageUp/PageDown, Home/End move the cursor; Enter pastes the
  // outlined row (Shift copies, Alt opens; nothing with no rows); Ctrl+P
  // pins, Ctrl+S marks secret, Delete drops (Ctrl+Shift+Delete clears),
  // Space reveals a secret; other text edits the search. Returns whether
  // the key was handled.
  function handleKey(event: var): bool {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    if (event.key === Qt.Key_Escape) {
      if (root.filterText)
        root.setFilter("")
      else
        root.close()
      return true
    } else if (ctrl && event.key === Qt.Key_P) {
      root.togglePinnedIndex(root.selectedIndex)
      return true
    } else if (ctrl && event.key === Qt.Key_S) {
      root.toggleSecretIndex(root.selectedIndex)
      return true
    } else if (event.key === Qt.Key_Delete) {
      if (ctrl && (event.modifiers & Qt.ShiftModifier))
        root.requestClearHistory()
      else
        root.removeDisplayIndex(root.selectedIndex)
      return true
    } else if (event.key === Qt.Key_Space && !root.filterText && root.displayModel.count > 0 && root.displayModel.get(root.selectedIndex).secret) {
      root.revealIndex(root.selectedIndex)
      return true
    } else if (Util.editsFilter(event, root.filterText)) {
      root.setFilter(Util.editedFilter(event, root.filterText))
      return true
    } else if (event.key === Qt.Key_Up) {
      root.select(-1)
      return true
    } else if (event.key === Qt.Key_Down) {
      root.select(1)
      return true
    } else if (event.key === Qt.Key_PageUp) {
      root.select(-6)
      return true
    } else if (event.key === Qt.Key_PageDown) {
      root.select(6)
      return true
    } else if (event.key === Qt.Key_Home) {
      root.selectAbsolute(0)
      return true
    } else if (event.key === Qt.Key_End) {
      root.selectAbsolute(root.displayModel.count - 1)
      return true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      // Enter acts on the outlined row; with no rows it does nothing.
      if (root.outlineShown && (event.modifiers & Qt.AltModifier))
        root.openIndex(root.selectedIndex)
      else if (root.outlineShown && (event.modifiers & Qt.ShiftModifier))
        root.copyIndex(root.selectedIndex)
      else if (root.outlineShown)
        root.activateIndex(root.selectedIndex)
      return true
    } else if (!ctrl && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
      root.setFilter(root.filterText + event.text)
      return true
    }
    return false
  }

  // A pointer click on row INDEX, pressed while it held KEY (its entry id):
  // moves the cursor there and pastes it. Refused (false) when the row no
  // longer holds KEY, so a click never lands on an entry that changed
  // between press and release. Hover never moves the cursor.
  function activateKey(index: int, key: string): bool {
    if (!key || index < 0 || index >= displayModel.count || displayModel.get(index).entryId !== key)
      return false
    root.cursorActive = true
    root.selectedIndex = index
    root.activateIndex(index)
    return true
  }

  // Pastes the row at display index.
  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count)
      return
    var row = displayModel.get(index)
    root.applySelected(row)
  }

  // Copies the row at display index to the clipboard without pasting.
  function copyIndex(index) {
    if (index < 0 || index >= displayModel.count)
      return
    var row = displayModel.get(index)
    root.copySelected(row)
  }

  // Opens the row at display index with omarchy-clipboard-open; secrets are
  // refused with a notice (opening would write them to a file).
  function openIndex(index) {
    if (index < 0 || index >= displayModel.count)
      return
    var row = displayModel.get(index)
    if (!ClipboardLogic.canOpen(row)) {
      root.showNotice("SECRETS CAN'T BE OPENED IN THE EDITOR")
      return
    }
    root.openSelected(row)
  }

  // A plain copy of the row: the model can change before a pending history
  // write finishes.
  function plainRow(row) {
    return {
      entryType: row.entryType,
      mime: row.mime,
      path: row.path,
      historyIndex: row.historyIndex
    }
  }

  // Runs Omarchy's paste script for a row: paste-file for images, paste-text
  // (by history index) for text; copyOnly only puts it on the clipboard.
  function pasteRow(row, copyOnly) {
    if (row.entryType === "image") {
      root.run([root.omarchyPath + "/bin/omarchy-clipboard-paste-file"].concat(copyOnly ? ["--copy-only"] : []).concat([row.mime, row.path]))
    } else {
      // Secrets have no display text; the script reads the entry by index.
      root.run([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", copyOnly ? "--copy-only" : "--shift-insert", "--history-index", String(row.historyIndex)])
    }
  }

  // Closes the picker and pastes the row once any pending history write is done.
  function applySelected(row) {
    if (!row)
      return
    root.opened = false
    var plain = root.plainRow(row)
    root.whenSaved(function () {
      root.pasteRow(plain, false)
    })
  }

  // Closes the picker and copies the row once any pending history write is done.
  function copySelected(row) {
    if (!row)
      return
    root.opened = false
    var plain = root.plainRow(row)
    root.whenSaved(function () {
      root.pasteRow(plain, true)
    })
  }

  // Closes the picker and opens the entry with omarchy-clipboard-open once any
  // pending history write is done.
  function openSelected(row) {
    if (!row)
      return
    root.opened = false
    var plain = root.plainRow(row)
    root.whenSaved(function () {
      root.run([root.omarchyPath + "/bin/omarchy-clipboard-open", "--history-index", String(plain.historyIndex)])
    })
  }

  Component.onCompleted: {
    if (root.windowEnabled) {
      var windowComponent = Qt.createComponent(Qt.resolvedUrl("ClipboardWindow.qml"))
      if (windowComponent.status === Component.Ready)
        root.view = windowComponent.createObject(root, {
          root: root
        })
      else
        console.warn("clipboard: window failed to load:", windowComponent.errorString())
    }
    if (root.captureEnabled)
      initProc.running = true
  }

  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: {
      root.nowMs = Date.now()
      root.expireNow()
    }
  }

  // Safety net: if a write never reports back (FileView may merge quick
  // writes), release the queue instead of holding pastes forever. Long
  // enough that a slow disk finishes first.
  Timer {
    id: saveWatchdog
    interval: 5000
    onTriggered: {
      root.pendingSaves = 0
      root.finishSave()
    }
  }

  // Clears the hint-line notice three seconds after showNotice.
  Timer {
    id: noticeTimer
    interval: 3000
    onTriggered: root.notice = ""
  }

  ListModel {
    id: rowsModel
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var raw = text()
      if (root.pendingSaves > 0 || root.savedTexts.indexOf(raw) >= 0)
        return
      root.loadHistory(raw)
    }
    onLoadFailed: {
      // A failed reload while our own write is pending must not wipe history.
      if (root.pendingSaves > 0)
        return
      root.loadHistory("[]")
    }
    onSaved: root.finishSave()
    onSaveFailed: root.finishSave()
    onFileChanged: reload()
  }

  // Reap watchers left behind by a previous shell instance, then start our
  // own. The pdeathsig on the watchers makes the kernel kill them whenever
  // the shell exits, however it exits, so no further lifecycle management.
  Process {
    id: initProc
    command: ["pkill", "-f", "wl-paste .*--watch .*/shell/plugins/clipboard/capture\\.sh"]
    onExited: {
      currentProc.running = true
      textWatchProc.running = true
      imageWatchProc.running = true
    }
  }

  Process {
    id: currentProc
    command: [root.captureScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.addClipboardJson(text)
    }
  }

  Process {
    id: textWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "text", "--watch", root.captureScript, "text"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function (data) {
        root.addClipboardJson(data)
      }
    }
  }

  Process {
    id: imageWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "image/png", "--watch", root.captureScript, "image/png"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function (data) {
        root.addClipboardJson(data)
      }
    }
  }

  // A watcher that dies takes clipboard history with it, silently: copying still
  // works, the picker still opens, and the old entries are all still there, so
  // nothing recorded until the next shell reload. Bring it back instead.
  Timer {
    id: watchRestartTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (!textWatchProc.running)
        textWatchProc.running = true
      if (!imageWatchProc.running)
        imageWatchProc.running = true
    }
  }

  // Menu-like entrance (fade + slight scale), unless Aranea motion is off
  // (shared Aranea.MotionState).
  property bool motionEnabled: Aranea.MotionState.motionEnabled

  // Nerd Font icon for a row kind (link, path, code, image; text otherwise).
  function kindGlyph(kind) {
    if (kind === "link")
      return String.fromCodePoint(0xf0337)
    if (kind === "path")
      return String.fromCodePoint(0xf024b)
    if (kind === "code")
      return String.fromCodePoint(0xf0169)
    if (kind === "image")
      return String.fromCodePoint(0xf02e9)
    return String.fromCodePoint(0xf09a8)
  }

  // Key-hint line for the current state and the row under the cursor.
  function hintText() {
    if (root.notice)
      return root.notice
    if (displayModel.count === 0)
      return root.filterText ? "ESC CLEAR SEARCH" : "ESC CLOSE"
    var row = root.selectedIndex >= 0 && root.selectedIndex < displayModel.count ? displayModel.get(root.selectedIndex) : null
    var parts = ["↑↓ SELECT", "ENTER PASTE", "⇧ENTER COPY", "^P " + (row && row.pinned ? "UNPIN" : "PIN")]
    if (row && row.secret && !root.filterText)
      parts.push("SPACE " + (root.revealedIndex === root.selectedIndex ? "HIDE" : "REVEAL"))
    if (row && row.kind !== "image")
      parts.push("^S " + (row.secret ? "NOT SECRET" : "SECRET"))
    parts.push("DEL DROP")
    return parts.join("  ·  ")
  }
}
