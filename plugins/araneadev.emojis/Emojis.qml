// Aranea emoji picker: a clone of Omarchy's emoji overlay (omarchy.emojis)
// in the Aranea menu language, with a RECENT row and the selected emoji's
// name. Search and data are Omarchy's own (EmojiSearch.js, emojis.json);
// inserting still goes through omarchy-menu-emoji-insert.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "EmojiSearch.js" as EmojiSearch
import "EmojiLogic.js" as EmojiLogic

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  // The cursor is either in the RECENT row or in the grid.
  property bool inRecents: false
  property int recentIndex: 0
  property var emojis: []
  property var filteredEmojis: []
  property var keywordsByEmoji: ({})
  property var recents: []

  readonly property string stateRoot: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/aranea"
  readonly property string recentsPath: stateRoot + "/emoji-recent.json"
  readonly property bool showRecents: !root.filterText && root.recents.length > 0

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int cardWidth: Math.min(Style.space(440), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)

  property int cellWidth: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  property int cellHeight: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  property int columns: Math.max(1, Math.floor((cardWidth - contentMargin * 2) / cellWidth))

  readonly property string selectedEmoji: {
    if (root.inRecents) return root.recents[root.recentIndex] || ""
    var item = root.filteredEmojis[root.selectedIndex]
    return item ? item.e : ""
  }
  readonly property string selectedName: root.selectedEmoji ? EmojiLogic.emojiName(root.keywordsByEmoji[root.selectedEmoji] || "") : ""

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.recentIndex = 0
    root.inRecents = root.recents.length > 0
    root.cursorActive = true
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omarchy.emojis")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function loadEmojis(raw) {
    root.emojis = EmojiSearch.parseEmojis(raw)
    var map = {}
    for (var i = 0; i < root.emojis.length; i++) map[root.emojis[i].e] = root.emojis[i].k
    root.keywordsByEmoji = map
    if (root.opened) root.rebuildDisplay()
  }

  function rebuildDisplay() {
    // No cap below the data size, so the count and the grid cover every emoji.
    var out = EmojiSearch.filterEmojis(root.emojis, root.filterText, Math.max(1000, root.emojis.length))
    root.filteredEmojis = out

    displayModel.clear()
    for (var j = 0; j < out.length; j++) {
      displayModel.append({ emoji: out[j].e, index: j })
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0
    if (!root.showRecents) root.inRecents = false
    cursorActive = displayModel.count > 0 || root.inRecents

    Qt.callLater(function() {
      if (displayModel.count > 0 && !root.inRecents) resultGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
    })
  }

  function select(delta) {
    if (root.inRecents) {
      root.recentIndex = (root.recentIndex + delta + root.recents.length) % root.recents.length
      return
    }
    if (displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function selectRow(delta) {
    if (root.inRecents) {
      var nextRecent = root.recentIndex + delta * columns
      if (nextRecent >= root.recents.length) {
        // Down out of the recent row enters the grid at the same column.
        if (displayModel.count === 0) return
        root.inRecents = false
        root.selectedIndex = Math.min(root.recentIndex % columns, displayModel.count - 1)
        resultGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
      } else if (nextRecent >= 0) {
        root.recentIndex = nextRecent
      }
      return
    }
    if (displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
      resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
      return
    }
    var newIndex = selectedIndex + delta * columns
    if (newIndex < 0) {
      // Up out of the first grid row enters the recent row.
      if (root.showRecents) {
        root.inRecents = true
        root.recentIndex = Math.min(selectedIndex % columns, root.recents.length - 1)
        return
      }
      newIndex = 0
    }
    if (newIndex >= displayModel.count) newIndex = displayModel.count - 1
    selectedIndex = newIndex
    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function selectPage(delta) {
    if (root.inRecents || displayModel.count === 0) return
    var visibleRows = Math.max(1, Math.floor(resultGrid.height / cellHeight))
    var newIndex = selectedIndex + delta * columns * visibleRows
    if (newIndex < 0) newIndex = 0
    if (newIndex >= displayModel.count) newIndex = displayModel.count - 1
    selectedIndex = newIndex
    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.inRecents = false
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function remember(emoji) {
    root.recents = EmojiLogic.pushRecent(root.recents, emoji, 16)
    recentsFile.setText(EmojiLogic.serializeRecents(root.recents))
  }

  // Enter inserts into the focused window (Omarchy's command); Shift+Enter
  // only copies it.
  function applySelected(emoji, copyOnly) {
    if (!emoji) return
    root.remember(emoji)
    root.dismiss()
    if (copyOnly) Quickshell.execDetached(["wl-copy", "--", emoji])
    else Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-menu-emoji-insert", emoji])
  }

  function hintText() {
    return ["←↑↓→ MOVE", "ENTER INSERT", "⇧ENTER COPY", "ESC " + (root.filterText ? "CLEAR" : "CLOSE")].join("  ·  ")
  }

  ListModel { id: displayModel }

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

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-emojis"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
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

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.selectRow(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.selectRow(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.selectPage(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.selectPage(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive) root.applySelected(root.selectedEmoji, (event.modifiers & Qt.ShiftModifier) !== 0)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      OverlayChrome {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        title: "EMOJI"
        subtitle: "SEARCH // INSERT // COPY"
        counts: String(displayModel.count)
        searchText: root.filterText
        searchPlaceholder: "Search emojis…"
        hints: root.opened ? root.hintText() : ""
        fontFamily: root.fontFamily
        foreground: root.foreground
        accent: root.selectedText

        Column {
          anchors.fill: parent
          spacing: Style.space(6)

          component Caption: Text {
            textFormat: Text.PlainText
            color: Util.alpha(root.foreground, 0.58)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.Medium
            font.letterSpacing: 0.20
          }

          component Cell: Rectangle {
            id: cell
            property string glyph: ""
            property bool hasCursor: false
            signal picked()
            width: root.cellWidth
            height: root.cellHeight
            radius: root.cornerRadius
            color: hasCursor ? root.selectedBackground : "transparent"
            // Mint ring on the selected cell (the menu's rail does not fit a grid).
            border.width: hasCursor ? 1.5 : 0
            border.color: root.selectedText

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: cell.glyph
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: cell.picked()
            }
          }

          Caption {
            visible: root.showRecents
            text: "RECENT"
          }

          Flow {
            visible: root.showRecents
            width: parent.width
            Repeater {
              model: root.showRecents ? root.recents : []
              delegate: Cell {
                required property string modelData
                required property int index
                glyph: modelData
                hasCursor: root.inRecents && root.recentIndex === index
                onPicked: root.applySelected(modelData, false)
              }
            }
          }

          Caption {
            text: root.filterText ? "RESULTS  ·  " + displayModel.count : "ALL"
          }

          GridView {
            id: resultGrid
            width: parent.width
            height: parent.height - y - nameLine.height - parent.spacing
            model: displayModel
            clip: true
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            boundsBehavior: Flickable.StopAtBounds

            delegate: Cell {
              required property int index
              required property string emoji
              glyph: emoji
              hasCursor: root.cursorActive && !root.inRecents && index === root.selectedIndex
              onPicked: {
                root.inRecents = false
                root.selectedIndex = index
                root.applySelected(emoji, false)
              }
            }

            Column {
              anchors.centerIn: parent
              spacing: Style.space(8)
              visible: displayModel.count === 0

              Text {
                text: "󰈉"
                color: root.selectedText
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: "No matches for “" + root.filterText + "”"
                color: root.foreground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
              }
            }
          }

          // Name of the emoji under the cursor.
          Text {
            id: nameLine
            width: parent.width
            textFormat: Text.PlainText
            text: root.selectedEmoji ? root.selectedEmoji + "  " + root.selectedName : " "
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
