// Compatibility shim for the shared Aranea picker chrome.
import QtQuick
import "../araneadev.shared" as Shared
import qs.Commons

Item {
  id: root

  // Header title.
  property string title: ""
  // Header subtitle.
  property string subtitle: ""
  // Optional count label.
  property string counts: ""
  // Current filter text.
  property string searchText: ""
  // Empty-search hint.
  property string searchPlaceholder: "Search…"
  // Keyboard hint strip.
  property string hints: ""
  // Font family used by the frame.
  property string fontFamily: Style.font.menuFamily
  // Base foreground color.
  property color foreground: Color.menu.text
  // Accent color for active search/count states.
  property color accent: Color.menu.selectedText
  // Content rendered between search and hints.
  default property alias content: frame.content

  Shared.OverlayChrome {
    id: frame
    anchors.fill: parent
    title: root.title
    subtitle: root.subtitle
    counts: root.counts
    searchText: root.searchText
    searchPlaceholder: root.searchPlaceholder
    hints: root.hints
    fontFamily: root.fontFamily
    foreground: root.foreground
    accent: root.accent
  }
}
