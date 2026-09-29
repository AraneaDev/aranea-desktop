// Polkit request, identity, and details presentation.
// Authentication input and focus/animation policy remain in PolkitWindow.qml.
// qmllint disable missing-property unqualified
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "PolkitLogic.js" as PolkitLogic

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
  property string fontFamily: Style.font.menuFamily
  // Public contract member.
  property color foreground: Color.polkit.text
  // Public contract member.
  property color dim: Util.alpha(Color.polkit.text, 0.58)
  // Public contract member.
  property color accent: Color.polkit.accent
  // Public contract member.
  property real letterSpacing: 0
  // Public contract member.
  signal detailsToggled
  // Public contract member.
  signal keyPressed(var event)

  spacing: Style.space(10)

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(10)

    Image {
      Layout.preferredWidth: Style.space(22)
      Layout.preferredHeight: Style.space(22)
      source: root.glyphSource
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
        text: "AUTHENTICATION REQUIRED"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.weight: Font.Medium
        font.letterSpacing: root.letterSpacing
        elide: Text.ElideRight
      }
      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: "SYSTEM // PRIVILEGED"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        font.letterSpacing: root.letterSpacing
        elide: Text.ElideRight
      }
    }
  }

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
    font.family: root.fontFamily
    font.pixelSize: Style.font.subtitle
    wrapMode: Text.Wrap
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
      textFormat: Text.PlainText
      text: (root.detailsOpen ? "▴" : "▾") + " DETAILS"
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.weight: Font.Medium
      font.letterSpacing: root.letterSpacing
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.detailsToggled()
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
