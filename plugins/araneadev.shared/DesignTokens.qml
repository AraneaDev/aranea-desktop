// Canonical semantic design tokens exposed to shared QML components.
// qmllint disable missing-property
pragma Singleton
import QtQuick
import qs.Commons

QtObject {
  // Primary accent colour.
  readonly property color accent: Color.accent
  // Secondary accent used by selected menu text.
  readonly property color accentSecondary: Color.menu.selectedText
  // Base background colour.
  readonly property color background: Color.background
  // Default foreground colour.
  readonly property color foreground: Color.foreground
  // Urgent and attention colour.
  readonly property color urgent: Color.urgent
  // Shared surface border colour.
  readonly property color surfaceBorder: Color.tooltip.border
  // Shared panel corner radius.
  readonly property int cornerRadius: Style.cornerRadius
  // Shared panel padding.
  readonly property int panelPadding: Style.spacing.panelPadding
  // Shared row horizontal padding.
  readonly property int rowPadding: Style.spacing.rowPaddingX
  // Whether motion effects are enabled.
  readonly property bool motionEnabled: true
}
