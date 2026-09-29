// Authentication presentation for the lock surface.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons

Item {
  id: root
  // Public contract member.
  property string passwordValue: ""
  // Public contract member.
  property bool responseVisible: false
  // Public contract member.
  property bool responseEnabled: true
  // Public contract member.
  property bool fingerprintVisible: false
  // Public contract member.
  property bool fingerprintActive: false
  // Public contract member.
  property string failureMessage: ""
  // Public contract member.
  property int shakeOffset: 0
  // Public contract member.
  property string fontFamily: Style.font.family
  // Public contract member.
  property color foreground: Color.lock.text
  // Public contract member.
  signal passwordSubmitted(string value)
  // Public contract member.
  signal fingerprintRequested
  // Public contract member.
  signal cancelRequested
  implicitHeight: content.implicitHeight
  Column {
    id: content
    anchors.horizontalCenter: parent.horizontalCenter
    width: parent.width
    spacing: Style.space(8)
    Text {
      visible: root.failureMessage !== ""
      text: root.failureMessage
      color: Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      width: parent.width
    }
    TextInput {
      width: parent.width
      text: root.passwordValue
      echoMode: root.responseVisible ? TextInput.Normal : TextInput.Password
      enabled: root.responseEnabled
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onAccepted: root.passwordSubmitted(text)
    }
    Text {
      visible: root.fingerprintVisible
      text: root.fingerprintActive ? "TOUCH SENSOR" : "USE PASSWORD"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      MouseArea {
        anchors.fill: parent
        onClicked: root.fingerprintRequested()
      }
    }
  }
}
