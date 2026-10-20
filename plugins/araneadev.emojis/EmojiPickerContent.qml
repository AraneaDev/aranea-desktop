// Emoji picker presentation: overlay chrome, recents, results, and footer.
// Filtering, recents persistence, keyboard navigation, and insertion remain
// owned by Emojis.qml. The mint outline marks the keyboard cursor; hover
// only fills (gated by PointerMoveGate) and clicks are keyed by emoji and
// settled, in the RECENT row and the grid alike.
// qmllint disable missing-property unqualified

import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Item {
  id: contentObject

  // Current search text shown by the overlay chrome.
  property string filterText: ""
  // Emoji result model supplied by Emojis.qml.
  property var resultModel: null
  // Recent emoji list supplied by Emojis.qml.
  property var recentModel: []
  // Whether the recent section should be shown.
  property bool showRecents: false
  // Selected result index.
  property int selectedIndex: -1
  // Whether the keyboard outline shows.
  property bool cursorActive: false
  // The gate that tells real pointer moves from cells moving under a still
  // pointer; the window shares its own, else the content's.
  property var pointerGate: ownGate
  // When the cells last changed under a still pointer (Emojis.qml's
  // layoutChangedAt), 0 for never.
  property real layoutChangedAt: 0
  // The RECENT cell the pointer really moved onto (hover fill), -1 for none.
  property int hoveredRecent: -1
  // The emoji that RECENT cell held when hovered.
  property string hoveredRecentKey: ""
  // Whether the current cursor belongs to recents.
  property bool inRecents: false
  // Selected recent index.
  property int recentIndex: -1
  // Selected emoji glyph.
  property string selectedEmoji: ""
  // Readable name for the selected emoji.
  property string selectedName: ""
  // Footer and keyboard guidance text.
  property string hintText: ""
  // Font family used by picker components.
  property string fontFamily: Aranea.Typography.uiFamily
  // Main picker foreground colour.
  property color foreground: Commons.Color.menu.text
  // Selected result foreground colour.
  property color selectedText: Commons.Color.menu.selectedText
  // Selected result background colour.
  property color selectedBackground: Commons.Color.menu.selectedBackground
  // Cell width supplied by Emojis.qml.
  property int cellWidth: Style.space(44)
  // Cell height supplied by Emojis.qml.
  property int cellHeight: Style.space(44)
  // Grid columns (Emojis.qml).
  property int columns: 1
  // Shared corner radius for result cells.
  property real cornerRadius: Style.cornerRadius

  // Current result-grid height used by page navigation in Emojis.qml.
  readonly property real resultHeight: resultGrid.height
  // The result grid (tests read its cells).
  readonly property alias grid: resultGrid
  // The RECENT row's cells (tests read them).
  readonly property alias recentCells: recentRepeater

  // Emitted for a settled click on RECENT cell INDEX that still holds KEY.
  signal recentPicked(int index, string key)
  // Emitted for a settled click on result cell INDEX that still holds KEY.
  signal resultPicked(int index, string key)

  // Drops the RECENT row's hover fill.
  function clearRecentHover(): void {
    contentObject.hoveredRecent = -1
    contentObject.hoveredRecentKey = ""
  }

  onLayoutChangedAtChanged: contentObject.clearRecentHover()

  // Scroll a result into view after keyboard navigation.
  function reveal(index: int): void {
    resultGrid.positionViewAtIndex(index, GridView.Contain)
  }

  Aranea.OverlayChrome {
    refined: true
    anchors.fill: parent
    title: "EMOJI"
    subtitle: "SEARCH // INSERT // COPY"
    counts: resultModel ? String(resultModel.count) : "0"
    searchText: contentObject.filterText
    searchPlaceholder: "Search emojis…"
    hints: contentObject.hintText
    fontFamily: contentObject.fontFamily
    foreground: contentObject.foreground
    accent: contentObject.selectedText

    Column {
      anchors.fill: parent
      spacing: Style.space(6)

      Caption {
        visible: contentObject.showRecents
        text: "RECENT"
      }

      Flow {
        visible: contentObject.showRecents
        width: contentObject.columns * contentObject.cellWidth
        // Split the remainder of the content width on both sides.
        x: Math.round((parent.width - width) / 2)
        Repeater {
          id: recentRepeater
          model: contentObject.showRecents ? contentObject.recentModel : []
          delegate: EmojiCell {
            required property string modelData
            required property int index
            objectName: "recentCell"
            glyph: modelData
            hasCursor: contentObject.cursorActive && contentObject.inRecents && contentObject.recentIndex === index
            hovered: contentObject.hoveredRecent === index && contentObject.hoveredRecentKey === modelData
            pointerGate: contentObject.pointerGate
            layoutChangedAt: contentObject.layoutChangedAt
            onHoverMoved: function (key) {
              contentObject.hoveredRecent = index
              contentObject.hoveredRecentKey = key
            }
            onHoverLeft: if (contentObject.hoveredRecent === index)
              contentObject.clearRecentHover()
            onPicked: function (key) {
              contentObject.recentPicked(index, key)
            }
          }
        }
      }

      Caption {
        text: contentObject.filterText ? "RESULTS  ·  " + (contentObject.resultModel ? contentObject.resultModel.count : 0) : "ALL"
      }

      EmojiGrid {
        id: resultGrid
        width: contentObject.columns * contentObject.cellWidth
        // Split the remainder of the content width on both sides.
        x: Math.round((parent.width - width) / 2)
        height: parent.height - y - nameLine.height - parent.spacing
        model: contentObject.resultModel
        filterText: contentObject.filterText
        selectedIndex: contentObject.selectedIndex
        cursorActive: contentObject.cursorActive
        inRecents: contentObject.inRecents
        fontFamily: contentObject.fontFamily
        cellWidth: contentObject.cellWidth
        cellHeight: contentObject.cellHeight
        cornerRadius: contentObject.cornerRadius
        selectedBackground: contentObject.selectedBackground
        selectedText: contentObject.selectedText
        foreground: contentObject.foreground
        pointerGate: contentObject.pointerGate
        layoutChangedAt: contentObject.layoutChangedAt
        onPicked: function (index, key) {
          contentObject.resultPicked(index, key)
        }
      }

      // Name of the emoji under the cursor.
      EmojiPickerChrome {
        id: nameLine
        width: parent.width
        selectedName: contentObject.selectedEmoji ? contentObject.selectedEmoji + "  " + contentObject.selectedName : " "
        showFilter: false
        fontFamily: contentObject.fontFamily
        foreground: contentObject.foreground
      }
    }
  }

  // The content's own gate, used when the window shares none (tests).
  PointerMoveGate {
    id: ownGate
    referenceItem: contentObject
  }

  component Caption: Aranea.InkText {
    horizontalAlignment: Text.AlignLeft
    textFormat: Text.PlainText
    color: Util.alpha(contentObject.foreground, Aranea.DesignTokens.secondaryOpacity)
    font.family: contentObject.fontFamily
    font.pixelSize: Style.font.caption
    font.weight: Font.Medium
    font.letterSpacing: 0.20
  }
}
