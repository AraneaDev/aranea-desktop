// Polkit request, identity, and details presentation.
// Authentication input and focus/animation policy remain in PolkitWindow.qml.
// A pointer click on DETAILS within settleMs of the request opening or of
// the card shifting under a still pointer is ignored unless the pointer
// really moved onto it since (ClickSettle).
// qmllint disable missing-property unqualified
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "PolkitLogic.js" as PolkitLogic
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

ColumnLayout {
  id: root

  // Public contract member.
  property string currentMessage: ""
  // Public contract member.
  property string currentPrompt: ""
  // Public contract member.
  property string currentSupplementary: ""
  // Public contract member.
  property bool supplementaryIsError: false
  // Public contract member.
  property bool responseRequired: false
  // Public contract member.
  property bool responseVisible: false
  // Public contract member.
  property bool detailsOpen: false
  // Public contract member.
  property string identityText: ""
  // Public contract member.
  property string identityCount: ""
  // Public contract member.
  property string targetText: ""
  // Public contract member.
  property string actionDescription: ""
  // Public contract member.
  property string currentActionId: ""
  // Public contract member.
  property string actionVendor: ""
  // Public contract member.
  property url glyphSource: ""
  // Public contract member.
  property string fontFamily: Aranea.Typography.uiFamily
  // Public contract member.
  property color foreground: Color.polkit.text
  // Public contract member.
  property color dim: Util.alpha(Color.polkit.text, 0.58)
  // Public contract member.
  property color accent: Color.polkit.accent
  // Public contract member.
  property real letterSpacing: 0
  // When the request opened (Date.now()), for the DETAILS click settle.
  property real openedAt: 0
  // When the card last shifted under the pointer (Date.now()), for the
  // DETAILS click settle.
  property real layoutChangedAt: 0
  // How long after opening or a shift a DETAILS click is ignored, in ms.
  property int settleMs: 300
  // When the pointer last really moved onto DETAILS (Date.now()), 0 for never.
  property real pointerMovedAt: 0
  // Public contract member.
  signal detailsToggled
  // Public contract member.
  signal keyPressed(var event)

  // Whether a pointer click on DETAILS counts (ClickSettle.clickSettled).
  function detailsClickSettled() {
    return ClickSettle.clickSettled({
      now: Date.now(),
      createdAt: root.openedAt,
      movedAt: root.pointerMovedAt,
      layoutChangedAt: root.layoutChangedAt,
      settleMs: root.settleMs
    })
  }

  spacing: Style.space(10)
  onOpenedAtChanged: {
    root.pointerMovedAt = 0
    detailsGate.reset()
  }

  // Filters synthetic hover from the card moving under a still pointer.
  PointerMoveGate {
    id: detailsGate
  }

  Aranea.BrandHeader {
    Layout.fillWidth: true
    title: "AUTHENTICATION REQUIRED"
    subtitle: "SYSTEM // PRIVILEGED"
    glyphSource: root.glyphSource
    fontFamily: root.fontFamily
    foreground: root.foreground
    accent: root.accent
    letterSpacing: root.letterSpacing
  }

  // The request and who it runs as read as one sentence: line spacing, not
  // a section gap.
  ColumnLayout {
    Layout.fillWidth: true
    spacing: 0

    Text {
      Layout.fillWidth: true
      textFormat: Text.StyledText
      text: PolkitLogic.requestMarkup(root.currentMessage, root.accent.toString())
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }

    Text {
      Layout.fillWidth: true
      visible: text.length > 0
      textFormat: Text.PlainText
      text: root.targetText
      color: root.accent
      font.family: Aranea.Typography.technicalFamily
      font.pixelSize: Style.font.subtitle
      wrapMode: Text.Wrap
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(8)
    Text {
      Layout.fillWidth: true
      textFormat: Text.PlainText
      text: PolkitLogic.contextLine(root.actionDescription, root.identityText, root.identityCount)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
    Text {
      id: detailsToggle
      objectName: "detailsToggle"
      textFormat: Text.PlainText
      text: String.fromCodePoint(root.detailsOpen ? 0x25b4 : 0x25be) + " DETAILS"
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.weight: Font.Medium
      font.letterSpacing: root.letterSpacing
      Aranea.HoverTint {
        z: -1
        anchors.margins: -Style.space(3)
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.detailsClickSettled())
          root.detailsToggled()
      }
      HoverHandler {
        id: detailsHover
        onPointChanged: if (detailsHover.hovered && detailsGate.moved(detailsToggle, {
          x: detailsHover.point.position.x,
          y: detailsHover.point.position.y
        }))
          root.pointerMovedAt = Date.now()
      }
    }
  }

  ColumnLayout {
    Layout.fillWidth: true
    visible: root.detailsOpen
    PolkitDetails {
      rows: PolkitLogic.detailRows(root.currentActionId, root.actionVendor, PolkitLogic.commandFromMessage(root.currentMessage), root.currentMessage)
      fontFamily: root.fontFamily
      foreground: root.foreground
      dim: root.dim
      accent: root.accent
      letterSpacing: root.letterSpacing
      onKeyPressed: function (event) {
        root.keyPressed(event)
      }
    }
  }
}
