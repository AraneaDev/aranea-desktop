// Shared two-pixel status rail used by selectable and attention rows.
// qmllint disable missing-property
import QtQuick
import qs.Commons

Rectangle {
  // Colour of the status rail.
  property color railColor: DesignTokens.foreground
  implicitWidth: Style.space(2)
  color: railColor
}
