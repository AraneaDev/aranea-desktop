// One zone: daylight node, city, daylight strip and wall-clock time.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Item {
  id: zone
  // Runtime font token object; the host supplies its members dynamically.
  readonly property var fontSizes: Style.font
  // Plain row from Panel.worldView; no time or settings work lives here.
  property var row: ({})
  // Requests selection of this saved-city row.
  signal clicked
  // Requests a globe preview when the pointer enters this row.
  signal previewRequested
  implicitHeight: Style.space(30)
  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Aranea.DesignTokens.accent, 0.06)
    visible: !!zone.row.selected
  }
  Aranea.HoverTint {}
  Rectangle {
    objectName: "selectionBar"
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.topMargin: Style.space(4)
    anchors.bottomMargin: Style.space(4)
    width: Math.max(1, Style.space(2))
    color: Aranea.DesignTokens.accent
    visible: !!zone.row.selected
  }
  Text {
    id: node
    objectName: "zoneNode"
    x: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(14)
    text: zone.row.node === "day" || zone.row.node === "dusk" ? "◆" : "◇"
    color: zone.row.node === "day" ? Aranea.DesignTokens.accent : zone.row.node === "dusk" ? Aranea.DesignTokens.ceremonyGold : Util.alpha(Aranea.DesignTokens.foreground, 0.45)
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: zone.fontSizes.caption
  }
  Row {
    id: labels
    anchors.left: node.right
    anchors.leftMargin: Style.space(8)
    anchors.right: strip.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)
    Text {
      objectName: "zoneName"
      width: Math.max(0, Math.min(implicitWidth, labels.width - abbreviation.width - labels.spacing))
      textFormat: Text.PlainText
      text: zone.row.name || ""
      color: zone.row.home ? Aranea.DesignTokens.accent : Aranea.DesignTokens.foreground
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: zone.fontSizes.body
      elide: Text.ElideRight
    }
    Text {
      id: abbreviation
      textFormat: Text.PlainText
      text: zone.row.abbrev || ""
      anchors.baseline: parent.children[0].baseline
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.45)
      font.family: Aranea.Typography.technicalFamily
      font.pixelSize: zone.fontSizes.caption
    }
  }
  Canvas {
    id: strip
    objectName: "daylightStrip"
    width: Style.space(92)
    height: Style.space(9)
    anchors.right: time.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    readonly property var stops: zone.row.stops || []
    readonly property real now: Number(zone.row.now) || 0
    readonly property color dayColor: Aranea.DesignTokens.accent
    readonly property color duskColor: Aranea.DesignTokens.ceremonyGold
    readonly property color nightColor: Util.alpha(Aranea.DesignTokens.accentSecondary, 0.22)
    readonly property color tickColor: Aranea.DesignTokens.foreground
    function repaint() {
      if (visible)
        requestPaint()
    }
    onStopsChanged: repaint()
    onNowChanged: repaint()
    onVisibleChanged: repaint()
    onWidthChanged: repaint()
    onHeightChanged: repaint()
    onDayColorChanged: repaint()
    onDuskColorChanged: repaint()
    onNightColorChanged: repaint()
    onTickColorChanged: repaint()
    onPaint: {
      let ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      let g = ctx.createLinearGradient(0, 0, width, 0)
      let list = stops.length ? stops : [
        {
          at: 0,
          tone: "night"
        },
        {
          at: 1,
          tone: "night"
        }
      ]
      for (let i = 0; i < list.length; i++)
        g.addColorStop(list[i].at, list[i].tone === "day" ? dayColor : list[i].tone === "dusk" ? duskColor : nightColor)
      ctx.fillStyle = g
      ctx.fillRect(0, (height - Style.space(3)) / 2, width, Style.space(3))
      ctx.fillStyle = tickColor
      ctx.fillRect(Math.min(width - 1, Math.max(0, now * width)), 0, Math.max(1, Style.space(1)), height)
    }
  }
  Text {
    id: time
    objectName: "zoneTime"
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(50)
    horizontalAlignment: Text.AlignRight
    text: zone.row.time || "—:—"
    color: zone.row.home ? Aranea.DesignTokens.accent : Aranea.DesignTokens.foreground
    font.family: Aranea.Typography.technicalFamily
    font.pixelSize: zone.fontSizes.body
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    onEntered: zone.previewRequested()
    onClicked: zone.clicked()
  }
}
