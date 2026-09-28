// Shared two-pixel status rail used by selectable and attention rows.
import QtQuick
import qs.Commons

Rectangle {
  property color railColor: Color.popups.text
  implicitWidth: Style.space(2)
  color: railColor
}
