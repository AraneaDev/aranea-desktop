// Authentication prompt presentation for polkit.
import QtQuick
import qs.Commons

Item {
  id: root
  property string currentMessage: ""
  property string currentPrompt: ""
  property string currentSupplementary: ""
  property bool supplementaryIsError: false
  property bool responseRequired: false
  property bool responseVisible: false
  property bool detailsOpen: false
  property string passwordValue: ""
  property string identityText: ""
  property string identityCount: ""
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.polkit.text
  signal responseSubmitted(string value)
  signal detailsToggled()
  signal identityChanged(int direction)
  signal cancelRequested()
  implicitHeight: content.implicitHeight
  Column {
    id: content
    anchors.fill: parent
    spacing: Style.space(8)
    Text { visible: root.currentMessage !== ""; text: root.currentMessage; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; wrapMode: Text.Wrap }
    Text { visible: root.identityText !== ""; text: root.identityText + root.identityCount; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
    TextInput { visible: root.responseRequired; width: parent.width; text: root.passwordValue; echoMode: root.responseVisible ? TextInput.Normal : TextInput.Password; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; onAccepted: root.responseSubmitted(text) }
    Text { visible: root.currentSupplementary !== ""; text: root.currentSupplementary; color: root.supplementaryIsError ? Color.urgent : root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.Wrap }
    Text { text: root.detailsOpen ? "HIDE DETAILS" : "SHOW DETAILS"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; MouseArea { anchors.fill: parent; onClicked: root.detailsToggled() } }
  }
}
