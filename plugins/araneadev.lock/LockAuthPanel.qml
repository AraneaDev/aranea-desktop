// Authentication presentation for the lock surface.
import QtQuick
import qs.Commons

Item {
  id: root
  property string passwordValue: ""
  property bool responseVisible: false
  property bool responseEnabled: true
  property bool fingerprintVisible: false
  property bool fingerprintActive: false
  property string failureMessage: ""
  property int shakeOffset: 0
  property string fontFamily: Style.font.family
  property color foreground: Color.lock.text
  signal passwordSubmitted(string value)
  signal fingerprintRequested()
  signal cancelRequested()
  implicitHeight: content.implicitHeight
  Column {
    id: content
    anchors.horizontalCenter: parent.horizontalCenter
    width: parent.width
    spacing: Style.space(8)
    Text { visible: root.failureMessage !== ""; text: root.failureMessage; color: Color.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.caption; horizontalAlignment: Text.AlignHCenter; width: parent.width }
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
      MouseArea { anchors.fill: parent; onClicked: root.fingerprintRequested() }
    }
  }
}
