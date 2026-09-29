// Polkit authentication control: password entry or fingerprint prompt.
// Focus, submission and agent policy remain owned by PolkitWindow.qml.
// qmllint disable missing-property

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Rectangle {
  id: field

  // Whether to show the fingerprint sensor prompt instead of text input.
  property bool fingerprintMode: false
  // Height shared with the owning polkit window.
  property int fieldHeight: Style.space(44)
  // Corner radius for the input surface.
  property int cornerRadius: Style.cornerRadius
  // Foreground colour for text and field chrome.
  property color foreground: Color.polkit.text
  // Accent colour for the lock and fingerprint glyphs.
  property color accent: Color.polkit.accent
  // Error colour used during failed authentication.
  property color errorColor: Color.polkit.textError
  // Whether the field is displaying a failed attempt.
  property bool errorFlash: false
  // Whether password characters should be shown plainly.
  property bool responseVisible: false
  // Whether authentication has been submitted and input is read-only.
  property bool submitted: false
  // Whether the field accepts input from the active dialog.
  property bool dialogVisible: true
  // Current PAM prompt, retained as part of the field contract.
  property string currentPrompt: ""
  // Placeholder text resolved by the owning polkit logic.
  property string placeholderText: "Password"
  // Font family used by the field's text and glyphs.
  property string fontFamily: Style.font.family
  // Letter spacing for the fingerprint prompt.
  property real letterSpacing: 0.20

  // Password text entered by the user.
  readonly property alias passwordText: passwordInput.text

  // Forwarded key event for the window's submission policy.
  signal keyPressed(var event)

  // Focus the password input when authentication starts.
  function focusField(): void {
    passwordInput.forceActiveFocus()
  }

  // Clear the current password after a submission or failure.
  function clearPassword(): void {
    passwordInput.text = ""
  }

  Layout.fillWidth: true
  Layout.preferredHeight: field.fieldHeight
  radius: field.cornerRadius
  color: Util.alpha(field.foreground, 0.04)
  border.width: 1
  border.color: field.errorFlash ? field.errorColor : Util.alpha(field.foreground, passwordInput.activeFocus ? 0.22 : 0.10)

  Row {
    visible: field.fingerprintMode
    anchors.centerIn: parent
    spacing: Style.space(10)

    OpticalGlyph {
      width: Math.round(field.fieldHeight * 0.55)
      height: width
      text: "󰈷"
      fontFamily: field.fontFamily
      fontSize: Math.round(field.fieldHeight * 0.55)
      color: field.errorFlash ? field.errorColor : field.accent
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "TOUCH THE SENSOR"
      color: field.foreground
      font.family: field.fontFamily
      font.pixelSize: Style.font.caption
      font.weight: Font.Medium
      font.letterSpacing: field.letterSpacing
    }
  }

  Row {
    visible: !field.fingerprintMode
    anchors.fill: parent
    anchors.leftMargin: Style.space(12)
    anchors.rightMargin: Style.space(12)
    spacing: Style.space(10)

    Text {
      text: ""
      color: field.errorFlash ? field.errorColor : field.accent
      font.family: field.fontFamily
      font.pixelSize: Style.font.iconLarge
      width: Style.space(20)
      height: field.fieldHeight
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }

    Item {
      width: parent.width - Style.space(30)
      height: field.fieldHeight

      TextInput {
        id: passwordInput
        anchors.fill: parent
        verticalAlignment: TextInput.AlignVCenter
        activeFocusOnPress: true
        clip: true
        selectionColor: Util.alpha(field.accent, 0.45)
        selectedTextColor: field.foreground
        font.family: field.fontFamily
        font.pixelSize: Style.font.iconLarge
        echoMode: field.responseVisible ? TextInput.Normal : TextInput.Password
        passwordCharacter: "•"
        color: field.errorFlash ? field.errorColor : field.foreground
        cursorVisible: activeFocus && !field.submitted && !field.errorFlash
        readOnly: field.submitted || field.errorFlash
        enabled: field.dialogVisible
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          field.keyPressed(event)
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: field.errorFlash ? "Wrong" : (field.submitted ? "Checking..." : field.placeholderText)
        color: field.errorFlash ? field.errorColor : field.foreground
        opacity: field.errorFlash ? 1 : 0.36
        font.family: field.fontFamily
        font.pixelSize: Style.font.subtitle
        elide: Text.ElideRight
        visible: passwordInput.text.length === 0
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: passwordInput.forceActiveFocus()
      }
    }
  }
}
