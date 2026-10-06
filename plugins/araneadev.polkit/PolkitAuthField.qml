// Polkit authentication control: the shared Aranea.CredentialPrompt as the
// password field (lock glyph, placeholder, masking, Enter, Esc), or the
// fingerprint sensor prompt. The prompt shows the check inline: busy pulses
// it read-only, a failure says "Wrong" in the error colour, read-only.
// Focus, submission and agent policy remain owned by PolkitAgent.qml through
// PolkitWindow.qml.

import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Item {
  id: field

  // Whether to show the fingerprint sensor prompt instead of text input.
  property bool fingerprintMode: false
  // Height of the fingerprint prompt (the window's field height).
  property int fieldHeight: Style.space(44)
  // Foreground colour for text and field chrome.
  property color foreground: Color.polkit.text
  // Accent colour for the frame, the lock and the fingerprint glyph.
  property color accent: Color.polkit.accent
  // Error colour used during failed authentication.
  property color errorColor: Color.polkit.textError
  // Whether the field is displaying a failed attempt.
  property bool errorFlash: false
  // Whether password characters should be shown plainly.
  property bool responseVisible: false
  // Whether authentication has been submitted (the busy pulse, read-only).
  property bool submitted: false
  // Whether the field accepts input from the active dialog.
  property bool dialogVisible: true
  // Placeholder text resolved by the owning polkit logic.
  property string placeholderText: "Password"
  // Font family used by the fingerprint prompt.
  property string fontFamily: Aranea.Typography.uiFamily
  // Letter spacing for the fingerprint prompt.
  property real letterSpacing: 0.20
  // Corner radius of the fingerprint prompt's frame.
  property int cornerRadius: Aranea.DesignTokens.cornerRadius
  // Password text entered by the user.
  readonly property string passwordText: credential.texts.password || ""

  // Enter in the password field.
  signal authorize
  // Esc in the password field.
  signal cancel
  // Any other key in the password field (Tab, Shift+Tab) for the window's
  // key map; a handler sets event.accepted to take it.
  signal keyPressed(var event)

  // Focus the password input when authentication starts.
  function focusField(): void {
    var input = credential.inputAt(0)
    if (input)
      input.forceActiveFocus()
  }

  // Clear the current password after a submission or failure.
  function clearPassword(): void {
    credential.clearFields()
  }

  implicitHeight: field.fingerprintMode ? field.fieldHeight : credential.height
  height: implicitHeight

  Rectangle {
    objectName: "fingerprintPrompt"
    anchors.fill: parent
    visible: field.fingerprintMode
    radius: field.cornerRadius
    color: Util.alpha(field.foreground, 0.04)
    border.width: 1
    border.color: field.errorFlash ? field.errorColor : Util.alpha(field.foreground, 0.10)

    Row {
      anchors.centerIn: parent
      spacing: Style.space(10)

      OpticalGlyph {
        objectName: "fingerprintGlyph"
        width: Math.round(field.fieldHeight * 0.55)
        height: width
        text: String.fromCodePoint(0xf0237)
        fontFamily: Aranea.Typography.iconFamily
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
  }

  Aranea.CredentialPrompt {
    id: credential
    width: field.width
    visible: !field.fingerprintMode
    enabled: field.dialogVisible
    inlineStatus: true
    connectShown: false
    busy: field.submitted
    failed: field.errorFlash
    failedText: "Wrong"
    accentColor: field.accent
    foregroundColor: field.foreground
    urgentColor: field.errorColor
    fields: [
      {
        key: "password",
        label: "Password",
        placeholder: field.placeholderText,
        secret: !field.responseVisible,
        glyph: String.fromCodePoint(0xf023)
      }
    ]
    onSubmit: field.authorize()
    onCancel: field.cancel()
    onUnhandledKey: function (event) {
      field.keyPressed(event)
    }
  }
}
