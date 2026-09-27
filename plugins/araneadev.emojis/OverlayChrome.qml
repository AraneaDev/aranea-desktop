// Shared frame for the Aranea pickers (clipboard, emoji): the menu's header
// language (glyph, uppercase title, // subtitle), a search line, the content
// and a key-hint strip. Kept byte-identical in araneadev.clipboard and
// araneadev.emojis; tests/emojis.test.sh fails when the copies differ.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons

Item {
  id: chrome

  property string title: ""
  property string subtitle: ""
  property string counts: ""
  property string searchText: ""
  property string searchPlaceholder: "Search…"
  property string hints: ""
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  readonly property color dim: Util.alpha(foreground, 0.58)
  readonly property real letterSpacing: 0.20
  readonly property string glyphSource: "file://" + (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/current/theme/branding/marks/aranea-glyph.svg"

  default property alias content: body.data

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(10)

    // Header: glyph, title and subtitle, counts.
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(10)

      Image {
        Layout.preferredWidth: Style.space(22)
        Layout.preferredHeight: Style.space(22)
        source: chrome.glyphSource
        sourceSize: Qt.size(44, 44)
        fillMode: Image.PreserveAspectFit
        smooth: true
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: chrome.title
          color: chrome.foreground
          font.family: chrome.fontFamily
          font.pixelSize: Style.font.title
          font.weight: Font.Medium
          font.letterSpacing: chrome.letterSpacing
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: chrome.subtitle
          color: chrome.dim
          font.family: chrome.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.Medium
          font.letterSpacing: chrome.letterSpacing
          elide: Text.ElideRight
        }
      }

      Text {
        textFormat: Text.PlainText
        text: chrome.counts
        color: chrome.accent
        opacity: 0.8
        font.family: chrome.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        font.letterSpacing: chrome.letterSpacing
      }
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
