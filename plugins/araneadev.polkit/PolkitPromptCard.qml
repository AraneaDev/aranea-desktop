// Authentication prompt presentation for polkit.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons

Item {
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
  property string passwordValue: ""
  // Public contract member.
  property string identityText: ""
  // Public contract member.
  property string identityCount: ""
  // Public contract member.
  property string fontFamily: Style.font.menuFamily
  // Public contract member.
  property color foreground: Color.polkit.text
  // Public contract member.
  signal responseSubmitted(string value)
  // Public contract member.
  signal detailsToggled
  // Public contract member.
  signal identityChanged(int direction)
  // Public contract member.
  signal cancelRequested
  implicitHeight: content.implicitHeight
  Column {
    id: content
    anchors.fill: parent
    spacing: Style.space(8)
    Text {
      visible: root.currentMessage !== ""
      text: root.currentMessage
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
    }
    Text {
      visible: root.identityText !== ""
      text: root.identityText + root.identityCount
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    TextInput {
      visible: root.responseRequired
      width: parent.width
      text: root.passwordValue
      echoMode: root.responseVisible ? TextInput.Normal : TextInput.Password
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onAccepted: root.responseSubmitted(text)
    }
    Text {
      visible: root.currentSupplementary !== ""
      text: root.currentSupplementary
      color: root.supplementaryIsError ? Color.urgent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
    }
    Text {
      text: root.detailsOpen ? "HIDE DETAILS" : "SHOW DETAILS"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      MouseArea {
        anchors.fill: parent
        onClicked: root.detailsToggled()
      }
    }
  }
}
