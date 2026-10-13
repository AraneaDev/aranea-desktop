// Clear vector symbols for grouped bar controls, independent of font glyphs.
import QtQuick
import QtQuick.Shapes

Item {
  id: icon
  // Connections hub or system adjustment controls.
  property string kind: "connections"
  // Follow the owning button's semantic foreground.
  property color ink: DesignTokens.foreground
  Shape {
    anchors.centerIn: parent
    width: 24
    height: 24
    scale: Math.min(icon.width, icon.height) / 24
    antialiasing: true
    ShapePath {
      strokeColor: icon.ink
      strokeWidth: 1.8
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      fillColor: "transparent"
      PathSvg {
        path: icon.kind === "connections" ? "M12 7V12 M5 17V12H19V17 M12 12V17 M10 2H14V7H10Z M3 17H7V22H3Z M10 17H14V22H10Z M17 17H21V22H17Z" : "M3 5H6 M12 5H21 M3 12H13 M19 12H21 M3 19H8 M14 19H21 M12 5A3 3 0 1 0 6 5A3 3 0 1 0 12 5 M19 12A3 3 0 1 0 13 12A3 3 0 1 0 19 12 M14 19A3 3 0 1 0 8 19A3 3 0 1 0 14 19"
      }
    }
  }
}
