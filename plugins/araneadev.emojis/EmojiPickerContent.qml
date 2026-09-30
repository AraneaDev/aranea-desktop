// Emoji picker presentation: overlay chrome, recents, results, and footer.
// Filtering, recents persistence, keyboard navigation, and insertion remain
// owned by Emojis.qml.
// qmllint disable missing-property unqualified

import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Item {
  id: content

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
  // Whether keyboard selection styling is active.
  property bool cursorActive: false
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
  property string fontFamily: Style.font.menuFamily
  // Main picker foreground colour.
  property color foreground: Color.menu.text
  // Selected result foreground colour.
  property color selectedText: Color.menu.selectedText
  // Selected result background colour.
  property color selectedBackground: Color.menu.selectedBackground
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

  // Emitted when a recent emoji is chosen.
  signal recentPicked(string emoji)
  // Emitted when a result emoji is chosen.
  signal resultPicked(string emoji, int index)

  // Scroll a result into view after keyboard navigation.
  function reveal(index: int): void {
    resultGrid.positionViewAtIndex(index, GridView.Contain)
  }

  Aranea.OverlayChrome {
    anchors.fill: parent
    title: "EMOJI"
    subtitle: "SEARCH // INSERT // COPY"
    counts: resultModel ? String(resultModel.count) : "0"
    searchText: content.filterText
    searchPlaceholder: "Search emojis…"
    hints: content.hintText
    fontFamily: content.fontFamily
    foreground: content.foreground
    accent: content.selectedText

    Column {
      anchors.fill: parent
      spacing: Style.space(6)

      Caption {
        visible: content.showRecents
        text: "RECENT"
      }

      Flow {
        visible: content.showRecents
        width: content.columns * content.cellWidth
        // Split the remainder of the content width on both sides.
        x: Math.round((parent.width - width) / 2)
        Repeater {
          model: content.showRecents ? content.recentModel : []
          delegate: EmojiCell {
            required property string modelData
            required property int index
            glyph: modelData
            hasCursor: content.inRecents && content.recentIndex === index
            onPicked: content.recentPicked(modelData)
          }
        }
      }

      Caption {
        text: content.filterText ? "RESULTS  ·  " + (content.resultModel ? content.resultModel.count : 0) : "ALL"
      }

      EmojiGrid {
        id: resultGrid
        width: content.columns * content.cellWidth
        // Split the remainder of the content width on both sides.
        x: Math.round((parent.width - width) / 2)
        height: parent.height - y - nameLine.height - parent.spacing
        model: content.resultModel
        filterText: content.filterText
        selectedIndex: content.selectedIndex
        cursorActive: content.cursorActive
        inRecents: content.inRecents
        fontFamily: content.fontFamily
        cellWidth: content.cellWidth
        cellHeight: content.cellHeight
        cornerRadius: content.cornerRadius
        selectedBackground: content.selectedBackground
        selectedText: content.selectedText
        foreground: content.foreground
        onPicked: content.resultPicked(emoji, index)
      }

      // Name of the emoji under the cursor.
      EmojiPickerChrome {
        id: nameLine
        width: parent.width
        selectedName: content.selectedEmoji ? content.selectedEmoji + "  " + content.selectedName : " "
        showFilter: false
        fontFamily: content.fontFamily
        foreground: content.foreground
      }
    }
  }

  component Caption: Aranea.InkText {
    horizontalAlignment: Text.AlignLeft
    textFormat: Text.PlainText
    color: Util.alpha(content.foreground, 0.58)
    font.family: content.fontFamily
    font.pixelSize: Style.font.caption
    font.weight: Font.Medium
    font.letterSpacing: 0.20
  }
}
