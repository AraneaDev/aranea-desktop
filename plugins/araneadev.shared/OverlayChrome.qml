// Shared frame for the Aranea pickers (clipboard, emoji): the menu's header
// qmllint disable missing-property
// language (glyph, uppercase title, // subtitle), a search line, the content
// and a key-hint strip. Kept byte-identical in araneadev.clipboard and
// araneadev.emojis; tests/emojis.test.sh fails when the copies differ.

import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
  id: chrome

  // Header title, shown as given (the pickers pass uppercase text).
  property string title: ""
  // Dimmed line under the title.
  property string subtitle: ""
  // Accent-coloured text at the right end of the header (entry counts).
  property string counts: ""
  // Current filter text; drawn in the search line and brightens its border when set.
  property string searchText: ""
  // Shown dimmed in the search line while searchText is empty.
  property string searchPlaceholder: "Search…"
  // Key-hint text for the strip at the bottom.
  property string hints: ""
  // Font for every text in the frame; defaults to the menu font.
  property string fontFamily: Style.font.menuFamily
  // Main text colour; also the base for the dimmed colour and the search box tints.
  property color foreground: Color.menu.text
  // Colour of the counts and of the search glyph while a filter is set.
  property color accent: Color.menu.selectedText
  // foreground at 58% alpha, for the subtitle, hints and idle search glyph.
  readonly property color dim: Util.alpha(foreground, 0.58)
  // Letter spacing of the header, counts and hint texts.
  readonly property real letterSpacing: 0.20
  // file:// URL of the Aranea glyph in the current theme's branding
  // ($XDG_STATE_HOME, falling back to ~/.local/state).
  readonly property string glyphSource: RuntimePaths.glyphUrl

  // Children declared inside OverlayChrome land in the content area between
  // the search line and the hint strip.
  default property alias content: body.data

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(10)

    // Header: glyph, title and subtitle, counts.
    BrandHeader {
      Layout.fillWidth: true
      title: chrome.title
      subtitle: chrome.subtitle
      counts: chrome.counts
      fontFamily: chrome.fontFamily
      foreground: chrome.foreground
      accent: chrome.accent
      letterSpacing: chrome.letterSpacing
      glyphSource: chrome.glyphSource
    }

    // Search line.
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: searchRow.implicitHeight + Style.space(14)
      radius: Style.cornerRadius
      color: Util.alpha(chrome.foreground, 0.04)
      border.width: 1
      border.color: Util.alpha(chrome.foreground, chrome.searchText ? 0.22 : 0.10)

      RowLayout {
        id: searchRow
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(8)
        Text {
          textFormat: Text.PlainText
          text: "⌕"
          color: chrome.searchText ? chrome.accent : chrome.dim
          font.family: chrome.fontFamily
          font.pixelSize: Style.font.subtitle
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: chrome.searchText || chrome.searchPlaceholder
          color: chrome.foreground
          opacity: chrome.searchText ? 1 : 0.58
          font.family: chrome.fontFamily
          font.pixelSize: Style.font.subtitle
          elide: Text.ElideLeft
        }
      }
    }

    // Content supplied by the picker.
    Item {
      id: body
      Layout.fillWidth: true
      Layout.fillHeight: true
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Util.alpha(chrome.foreground, 0.10)
    }

    // Key hints for the current state.
    Text {
      Layout.fillWidth: true
      textFormat: Text.PlainText
      text: chrome.hints
      color: chrome.dim
      font.family: chrome.fontFamily
      font.pixelSize: Style.font.caption
      font.weight: Font.Medium
      font.letterSpacing: chrome.letterSpacing
      elide: Text.ElideRight
    }
  }
}
