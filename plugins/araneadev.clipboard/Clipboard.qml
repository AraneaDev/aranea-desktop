// Aranea clipboard: a clone of Omarchy's clipboard picker (omarchy.clipboard)
// in the Aranea menu language, with typed rows, pins and masked, expiring
// secrets. Capture, paste and copy still use Omarchy's scripts; rules live in
// ClipboardLogic.js.
// Overlay entry point of the araneadev.clipboard plugin (manifest.json); the
// Omarchy shell keeps it loaded and calls open()/close()/toggle() on summon
// and hide. It records clipboard history in the background even while closed.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "ClipboardLogic.js" as ClipboardLogic

Item {
  id: root

  // Omarchy install root ($OMARCHY_PATH), for its clipboard scripts.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  // Whether the picker window is shown.
  property bool opened: false
  // Current search text typed into the picker.
  property string filterText: ""
  // Cursor position in the displayed rows (display index, not history index).
  property int selectedIndex: 0
  // Whether the cursor is shown; keys that act on a row need it.
  property bool cursorActive: false
  // Whether the "clear history" confirmation dialog is open.
  property bool clearConfirmOpen: false
  // All history entries (ClipboardLogic entries), newest first, as saved to historyPath.
  property var history: []

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
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  // Colour laid over the screen behind the card.
  property color scrim: Color.menu.scrim
  // Background of the row under the cursor.
  property color selectedBackground: Color.menu.selectedBackground
  // Text colour of the row under the cursor; also the accent of the chrome.
  property color selectedText: Color.menu.selectedText
  // Corner radius of the card and rows.
  readonly property int cornerRadius: Style.cornerRadius
  // Font for all picker text (the menu font).
  property string fontFamily: Style.font.menuFamily
  // Inner padding of the card and the preview pane.
  property int contentMargin: Style.spacing.panelPadding
  // Header height; currently not read anywhere in this file.
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  // Spacing token; currently not read anywhere in this file.
  property int contentSpacing: Style.spacing.md
  // Card width: up to 875 scaled px, inside the screen gaps.
  property int cardWidth: Math.min(Style.space(875), panel.width - Style.gapsOut * 2)
  // Card height: up to 600 scaled px, inside the screen gaps.
  property int cardHeight: Math.min(Style.space(600), panel.height - Style.gapsOut * 2)
  // Height of one history row (title plus detail line).
  property int rowHeight: Math.max(Style.space(50), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  // Unpinned entries kept in history; pinned ones do not count.
  property int historyLimit: 300
  // Secrets leave history this long after capture (pinned ones stay).
  readonly property real secretTtlMs: Number(Quickshell.env("ARANEA_CLIPBOARD_SECRET_TTL_MS")) || 600000
  // Display index whose secret is revealed in the preview; any cursor move
  // masks it again.
  property int revealedIndex: -1
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
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
    Qt.callLater(function () {
      keyCatcher.forceActiveFocus()
    })
  }

  // Hides the picker and dismisses the clear confirmation.
  function close() {
    root.cancelClearHistory()
    root.opened = false
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
    root.updateHistory(ClipboardLogic.toggleSecret(root.history, displayModel.get(index).historyIndex))
  }

  // Toggles showing the secret at display index in the preview; no-op for non-secret rows.
  function revealIndex(index) {
    if (index < 0 || index >= displayModel.count || !displayModel.get(index).secret)
      return
    root.revealedIndex = root.revealedIndex === index ? -1 : index
  }

  // Our own writes come back through watchChanges; skipping that echo avoids
  // re-parsing (and re-detecting) the whole history after every change.
  property string lastSavedText: ""
  // Paste/copy read the history file by index, so they wait for a pending
  // write (Delete then Enter must not paste the neighbour from the old file).
  property bool saving: false
  // Paste/copy/open action waiting for the current history write to finish.
  property var pendingAction: null

  // Writes the history as pretty JSON to historyPath and marks a save as in flight.
  function saveHistory() {
    root.lastSavedText = JSON.stringify(root.history, null, 2) + "\n"
    root.saving = true
    historyFile.setText(root.lastSavedText)
  }

  // Clears the in-flight save flag and runs the pending action, if any.
  function finishSave() {
    root.saving = false
    var action = root.pendingAction
    root.pendingAction = null
    if (action)
      action()
  }

  // Runs action now, or after the in-flight save finishes (replacing any
  // action already waiting).
  function whenSaved(action) {
    if (root.saving)
      root.pendingAction = action
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
    clearConfirm.selectedIndex = 1
    root.clearConfirmOpen = true
  }

  // Closes the clear confirmation and returns focus to the key handler.
  function cancelClearHistory() {
    root.clearConfirmOpen = false
    root.disarmPointer()
    Qt.callLater(function () {
      keyCatcher.forceActiveFocus()
    })
  }

  // Removes every unpinned entry, saves, and resets the cursor.
  function confirmClearHistory() {
    // Pinned items are kept: clearing is for the churn, not what was chosen.
    root.history = ClipboardLogic.clearUnpinned(root.history)
    root.saveHistory()
    root.selectedIndex = 0
    root.cursorActive = false
    root.disarmPointer()
    root.clearConfirmOpen = false
    root.rebuildDisplay()
    Qt.callLater(function () {
      keyCatcher.forceActiveFocus()
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
      root.cursorActive = false
    } else if (root.selectedIndex >= displayModel.count - 1) {
      root.selectedIndex = displayModel.count - 2
    }

    root.disarmPointer()
    root.rebuildDisplay()
  }

  // Rebuilds the list model from history and the filter (at most 50 recent
  // rows plus pinned ones), clamps the cursor and scrolls it into view.
  function rebuildDisplay() {
    root.revealedIndex = -1
    // list changed: rows may have moved under the cursor
    var rows = ClipboardLogic.displayRows(root.history, root.filterText, 50, Date.now())

    displayModel.clear()
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      displayModel.append({
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
        path: row.path,
        mime: row.mime,
        historyIndex: row.historyIndex
      })
    }

    if (displayModel.count === 0)
      selectedIndex = 0
    else if (selectedIndex >= displayModel.count)
      selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0)
      selectedIndex = 0

    Qt.callLater(function () {
      if (displayModel.count > 0)
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  // Moves the cursor by delta rows, wrapping around; the first move only
  // shows the cursor at the top (or bottom for a negative delta).
  function select(delta) {
    if (displayModel.count === 0)
      return
    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  // Puts the cursor on index, clamped to the list, and scrolls to it.
  function selectAbsolute(index) {
    if (displayModel.count === 0)
      return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
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
    pointerGate.reset()
  }

  // Moves the cursor to the hovered row, but only after real pointer movement.
  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse))
      return
    root.cursorActive = true
    root.selectedIndex = index
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

  // Opens the row at display index with omarchy-clipboard-open.
  function openIndex(index) {
    if (index < 0 || index >= displayModel.count)
      return
    var row = displayModel.get(index)
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
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file"].concat(copyOnly ? ["--copy-only"] : []).concat([row.mime, row.path]))
    } else {
      // Secrets have no display text; the script reads the entry by index.
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", copyOnly ? "--copy-only" : "--shift-insert", "--history-index", String(row.historyIndex)])
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
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-open", "--history-index", String(plain.historyIndex)])
    })
  }

  Component.onCompleted: initProc.running = true

  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: root.expireNow()
  }

  ListModel {
    id: displayModel
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var raw = text()
      if (raw !== root.lastSavedText)
        root.loadHistory(raw)
    }
    onLoadFailed: root.loadHistory("[]")
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
  // (`off` in ~/.local/state/aranea/motion, or ARANEA_REDUCED_MOTION=1).
  property bool motionEnabled: Quickshell.env("ARANEA_REDUCED_MOTION") !== "1"
  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/aranea/motion"
    watchChanges: true
    printErrors: false
    onLoaded: root.motionEnabled = String(text() || "").trim() !== "off"
    onFileChanged: reload()
  }
  onOpenedChanged: if (opened && root.motionEnabled)
    openAnimation.restart()
  ParallelAnimation {
    id: openAnimation
    NumberAnimation {
      target: card
      property: "opacity"
      from: 0
      to: 1
      duration: 180
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: card
      property: "scale"
      from: 0.97
      to: 1
      duration: 180
      easing.type: Easing.OutCubic
    }
  }

  // Nerd Font icon for a row kind (link, path, code, image; text otherwise).
  function kindGlyph(kind) {
    if (kind === "link")
      return "󰌷"
    if (kind === "path")
      return "󰉋"
    if (kind === "code")
      return "󰅩"
    if (kind === "image")
      return "󰋩"
    return "󰦨"
  }

  // Key-hint line for the current state and the row under the cursor.
  function hintText() {
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

  PanelWindow {
    id: panel
    visible: root.opened
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.clearConfirmOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          if (root.clearConfirmOpen) {
            if (clearConfirm.handleKey(event))
              event.accepted = true
            return
          }

          var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
          if (event.key === Qt.Key_Escape) {
            if (root.filterText)
              root.setFilter("")
            else
              root.close()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_P) {
            root.togglePinnedIndex(root.selectedIndex)
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_S) {
            root.toggleSecretIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            if (ctrl && (event.modifiers & Qt.ShiftModifier))
              root.requestClearHistory()
            else
              root.removeDisplayIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Space && !root.filterText && displayModel.count > 0 && displayModel.get(root.selectedIndex).secret) {
            root.revealIndex(root.selectedIndex)
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
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
          } else if (event.key === Qt.Key_Home) {
            root.selectAbsolute(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectAbsolute(displayModel.count - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive && (event.modifiers & Qt.AltModifier))
              root.openIndex(root.selectedIndex)
            else if (root.cursorActive && (event.modifiers & Qt.ShiftModifier))
              root.copyIndex(root.selectedIndex)
            else if (root.cursorActive)
              root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0)
              root.cursorActive = true
            event.accepted = true
          } else if (!ctrl && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: clearConfirm

          anchors.fill: parent
          opened: root.clearConfirmOpen
          z: 10
          message: "Delete all unpinned clipboard items?"
          confirmText: "Delete"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelClearHistory()
          onConfirmed: root.confirmClearHistory()
        }
      }

      OverlayChrome {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        title: "CLIPBOARD"
        subtitle: "HISTORY // PASTE // PIN"
        counts: root.history.length + " ITEMS" + (root.pinnedCount > 0 ? "  ·  " + root.pinnedCount + " 📌" : "")
        searchText: root.filterText
        searchPlaceholder: "Search clipboard…"
        hints: root.opened ? root.hintText() : ""
        fontFamily: root.fontFamily
        foreground: root.foreground
        accent: root.selectedText

        Row {
          anchors.fill: parent
          spacing: 0

          Item {
            width: Math.round(parent.width * 0.48)
            height: parent.height
            clip: true

            ListView {
              id: resultList
              anchors.fill: parent
              anchors.rightMargin: root.contentMargin
              model: displayModel
              clip: true
              spacing: Style.space(2)
              boundsBehavior: Flickable.StopAtBounds

              section.property: "section"
              section.delegate: Item {
                required property string section
                width: ListView.view.width
                height: Style.space(26)
                // Hairline after the caption, as in the Aranea menu.
                Rectangle {
                  anchors.left: sectionCaption.right
                  anchors.leftMargin: Style.space(8)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: sectionCaption.verticalCenter
                  height: 1
                  color: Util.alpha(root.foreground, 0.10)
                }
                Text {
                  id: sectionCaption
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(4)
                  textFormat: Text.PlainText
                  text: parent.section === "pinned" ? "PINNED" : "RECENT"
                  color: Util.alpha(root.foreground, 0.58)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Medium
                  font.letterSpacing: 0.20
                }
              }

              delegate: Rectangle {
                id: row
                required property int index
                required property string kind
                required property bool secret
                required property bool pinned
                required property string title
                required property string detail
                required property string previewImage
                required property string colour

                readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

                width: ListView.view.width
                height: root.rowHeight
                radius: root.cornerRadius
                color: hasCursor ? root.selectedBackground : "transparent"

                Behavior on color {
                  ColorAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                  }
                }

                // Mint rail on the selected row, as in the Aranea menu.
                Rectangle {
                  visible: row.hasCursor
                  width: Style.space(2)
                  height: parent.height - Style.space(14)
                  radius: Style.space(1)
                  color: root.selectedText
                  opacity: 0.9
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(14)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(10)

                  Item {
                    width: Style.space(22)
                    height: parent.height

                    Image {
                      visible: row.previewImage.length > 0
                      anchors.centerIn: parent
                      width: parent.width
                      height: parent.width
                      source: row.previewImage
                      sourceSize: Qt.size(44, 44)
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                    }
                    Rectangle {
                      visible: row.colour.length > 0
                      anchors.centerIn: parent
                      width: Style.space(14)
                      height: Style.space(14)
                      radius: Style.space(3)
                      color: row.colour.length > 0 ? row.colour : "transparent"
                      border.width: 1
                      border.color: Util.alpha(root.foreground, 0.25)
                    }
                    Text {
                      visible: row.previewImage.length === 0 && row.colour.length === 0
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: row.secret ? "󰌾" : root.kindGlyph(row.kind)
                      color: row.hasCursor ? root.selectedText : Util.alpha(root.foreground, 0.7)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.icon
                    }
                  }

                  Text {
                    width: parent.width - Style.space(22) - detailText.width - parent.spacing * 2
                    height: parent.height
                    textFormat: Text.PlainText
                    text: row.title
                    color: row.hasCursor ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    verticalAlignment: Text.AlignVCenter
                  }

                  Text {
                    id: detailText
                    height: parent.height
                    textFormat: Text.PlainText
                    text: (row.pinned ? "📌 " : "") + row.detail
                    color: Util.alpha(root.foreground, 0.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    verticalAlignment: Text.AlignVCenter
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onPositionChanged: function (mouse) {
                    root.selectFromPointer(row.index, row, mouse)
                  }
                  onClicked: {
                    root.cursorActive = true
                    root.selectedIndex = row.index
                    root.activateIndex(row.index)
                  }
                }
              }
            }
          }

          // Preview of the selected item.
          Item {
            id: preview
            width: parent.width - Math.round(parent.width * 0.48)
            height: parent.height
            clip: true

            property var activeRow: displayModel.count > 0 && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count ? displayModel.get(root.selectedIndex) : null
            readonly property bool masked: !!activeRow && activeRow.secret && root.revealedIndex !== root.selectedIndex

            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: Style.normalBorderWidth
              color: Util.alpha(root.border, 0.28)
            }

            // Secret: masked until revealed with Space for this selection.
            Column {
              visible: preview.masked
              anchors.left: parent.left
              anchors.leftMargin: root.contentMargin
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)
              Text {
                textFormat: Text.PlainText
                text: "•••••••••••••••• · secret"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
              }
              Text {
                textFormat: Text.PlainText
                text: "SPACE TO REVEAL  ·  EXPIRES 10 MIN AFTER COPY"
                color: Util.alpha(root.foreground, 0.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 0.20
              }
            }

            // Colour swatch.
            Column {
              visible: !preview.masked && !!preview.activeRow && preview.activeRow.colour.length > 0
              anchors.left: parent.left
              anchors.leftMargin: root.contentMargin
              anchors.top: parent.top
              spacing: Style.space(10)
              Rectangle {
                width: Style.space(120)
                height: Style.space(80)
                radius: root.cornerRadius
                color: preview.activeRow && preview.activeRow.colour.length > 0 ? preview.activeRow.colour : "transparent"
                border.width: 1
                border.color: Util.alpha(root.foreground, 0.25)
              }
              Text {
                textFormat: Text.PlainText
                text: preview.activeRow ? preview.activeRow.colour : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
              }
            }

            // Text, code, links and paths (revealed secrets fetch their text
            // from history by index: display rows never carry it).
            Text {
              visible: !preview.masked && !!preview.activeRow && !preview.activeRow.previewImage && preview.activeRow.colour.length === 0
              anchors.fill: parent
              anchors.leftMargin: root.contentMargin
              textFormat: Text.PlainText
              text: !preview.activeRow ? "" : (preview.activeRow.secret ? ClipboardLogic.fullText(root.history[preview.activeRow.historyIndex]) : preview.activeRow.fullText)
              color: root.foreground
              font.family: preview.activeRow && preview.activeRow.kind === "code" ? "monospace" : root.fontFamily
              font.pixelSize: preview.activeRow && preview.activeRow.kind === "code" ? Style.font.body : Style.font.title
              wrapMode: Text.WrapAnywhere
              elide: Text.ElideRight
              verticalAlignment: Text.AlignTop
            }

            Image {
              visible: !preview.masked && !!preview.activeRow && preview.activeRow.previewImage.length > 0
              anchors.fill: parent
              anchors.leftMargin: root.contentMargin
              source: preview.activeRow ? preview.activeRow.previewImage : ""
              fillMode: Image.PreserveAspectFit
              verticalAlignment: Image.AlignTop
              asynchronous: true
              smooth: true
            }
          }
        }

        Column {
          anchors.centerIn: parent
          spacing: Style.space(8)
          visible: displayModel.count === 0

          Text {
            text: "󰅌"
            color: root.selectedText
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            text: root.history.length === 0 ? "Clipboard is empty" : "No matches for “" + root.filterText + "”"
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
          }
        }
      }
    }
  }
}
