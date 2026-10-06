// Presentational detail section. The host owns expansion, keyboard stops and
// layout stamps; activation requests a toggle without changing expanded.
import QtQuick
import qs.Commons
import qs.Ui
import "ClickSettle.js" as ClickSettle

Item {
  id: section

  // Heading label, kept as plain text.
  property string title: ""
  // Expansion state controlled by the host.
  property bool expanded: false
  // Whether the host's keyboard cursor targets this heading.
  property bool keyboardFocused: false
  // Host PointerMoveGate with its layoutChangedAt settling stamp.
  property var pointerGate: null
  // Detail rows, stacked with the common row spacing.
  default property alias content: contentSlot.data
  // Requests a host-owned expansion change from pointer or keyboard input.
  signal toggleRequested

  // Host keyboard activation bypasses pointer settling, as in Filament rows.
  function activate() {
    section.toggleRequested()
  }

  implicitWidth: Math.max(heading.implicitWidth, contentSlot.implicitWidth)
  implicitHeight: heading.height + (expanded && contentSlot.implicitHeight > 0 ? Style.space(16) + contentSlot.implicitHeight : 0)

  Item {
    id: heading
    objectName: "disclosureHeading"
    width: parent.width
    height: implicitHeight
    implicitHeight: Math.max(titleLabel.implicitHeight, indicator.implicitHeight) + Style.space(8)
    implicitWidth: titleLabel.implicitWidth + indicator.implicitWidth + Style.space(4)

    property real createdAt: 0
    property real pointerMovedAt: 0
    property bool pointerHovered: false
    readonly property var hoverGate: section.pointerGate || ownGate
    readonly property real layoutStamp: section.pointerGate ? Number(section.pointerGate.layoutChangedAt) || 0 : 0
    Component.onCompleted: createdAt = Date.now()
    onLayoutStampChanged: pointerHovered = false

    function clickSettled() {
      return ClickSettle.clickSettled({
        now: Date.now(),
        createdAt: heading.createdAt,
        movedAt: heading.pointerMovedAt,
        layoutChangedAt: heading.layoutStamp,
        settleMs: 300
      })
    }

    PointerMoveGate {
      id: ownGate
      referenceItem: heading.Window.contentItem
    }
    Rectangle {
      objectName: "hoverFill"
      anchors.fill: parent
      color: DesignTokens.hoverFill
      visible: heading.pointerHovered && section.enabled
    }
    Rectangle {
      objectName: "cursorOutline"
      anchors.fill: parent
      color: section.keyboardFocused ? Util.alpha(DesignTokens.accent, 0.08) : "transparent"
      border.width: section.keyboardFocused ? 1 : 0
      border.color: DesignTokens.accent
    }
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: Util.alpha(DesignTokens.foreground, 0.16)
    }
    Text {
      id: titleLabel
      anchors.left: parent.left
      anchors.right: indicator.left
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: section.title
      elide: Text.ElideRight
      color: DesignTokens.foreground
      // The host exposes its font tokens as a dynamic QObject.
      // qmllint disable missing-property
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      // qmllint enable missing-property
      font.bold: true
    }
    Text {
      id: indicator
      objectName: "disclosureIndicator"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: section.expanded ? "▾" : "▸"
      color: Util.alpha(DesignTokens.foreground, 0.55)
      // The host exposes its font tokens as a dynamic QObject.
      // qmllint disable missing-property
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      // qmllint enable missing-property
    }
    MouseArea {
      id: pointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (!containsMouse) {
        heading.pointerHovered = false
        ownGate.reset()
      }
      onPositionChanged: function (mouse) {
        if (!heading.hoverGate.moved(pointer, mouse))
          return
        heading.pointerHovered = true
        heading.pointerMovedAt = Date.now()
      }
      onClicked: if (heading.clickSettled())
        section.activate()
    }
  }

  Column {
    id: contentSlot
    objectName: "disclosureContent"
    y: heading.height + Style.space(16)
    width: parent.width
    height: section.expanded ? implicitHeight : 0
    visible: section.expanded
    spacing: Style.space(8)
  }
}
