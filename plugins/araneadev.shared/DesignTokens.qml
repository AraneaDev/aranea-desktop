pragma Singleton
import QtQuick
import qs.Commons

QtObject {
  readonly property color accent: Color.accent
  readonly property color accentSecondary: Color.menu.selectedText
  readonly property color background: Color.background
  readonly property color foreground: Color.foreground
  readonly property color urgent: Color.urgent
  readonly property color surfaceBorder: Color.tooltip.border
  readonly property int cornerRadius: Style.cornerRadius
  readonly property int panelPadding: Style.spacing.panelPadding
  readonly property int rowPadding: Style.spacing.rowPaddingX
  readonly property bool motionEnabled: true
}
