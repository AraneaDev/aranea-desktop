// Password and fingerprint field presentation for the lock surface.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root
  // Public contract member.
  property string passwordText: ""
  // Public contract member.
  property bool syncingPasswordText: false
  // Public contract member.
  property bool inputEnabled: true
  // Public contract member.
  property bool authenticatingPassword: false
  // Public contract member.
  property bool fingerprintConfigured: false
  // Public contract member.
  property string failureMessage: ""
  // Public contract member.
  property string placeholderText: "Enter Password"
  // Public contract member.
  property int fieldWidth: 381
  // Public contract member.
  property int fieldHeight: 67
  // Public contract member.
  property int fieldFontSize: Math.round(Style.font.heading * 1.125)
  // Public contract member.
  property int passwordDotFontSize: Math.round(Style.font.heading * 1.33)
  // Public contract member.
  property int passwordDotLetterSpacing: Math.round(Style.font.heading * 0.19)
  // Public contract member.
  property var inputBorderSpec: Border.none()
  // Public contract member.
  property int cornerRadius: Style.space(10)
  // Public contract member.
  property string fontFamily: Style.font.family
  // Public contract member.
  property color foreground: Color.lock.text
  // Public contract member.
  property color placeholderColor: Color.lock.placeholder
  // Public contract member.
  property color errorColor: Color.lock.textError
  // Public contract member.
  property color selectionColor: Color.lock.selection
  // Public contract member.
  property color accent: Color.lock.placeholder
  // Public contract member.
  signal submitPassword(string password)
  // Public contract member.
  signal passwordTextEdited(string password)
  // Public contract member.
  signal clearFailureRequested
  // Public contract member.
  signal wakeRequested

  // Public contract member.
  readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.implicitWidth + 12) : 0
  // Public contract member.
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0 ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth) : 1
  // Public contract member.
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0

  // Focuses the password input.
  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  // Synchronizes the input with the service-owned password value.
  function syncPasswordText() {
    if (passwordInput.text === passwordText)
      return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  onPasswordTextChanged: syncPasswordText()

  TextMetrics {
    id: dotMetrics
    font.family: root.fontFamily
    font.pixelSize: root.passwordDotFontSize
    font.letterSpacing: root.passwordDotLetterSpacing
    text: "●".repeat(passwordInput.text.length)
  }

  BorderSurface {
    id: inputField
    width: root.fieldWidth
    height: root.fieldHeight
    anchors.centerIn: parent
    color: Color.lock.background
    borderSpec: root.inputBorderSpec
    radius: root.cornerRadius
    clip: true

    TextInput {
      id: passwordInput
      anchors.fill: parent
      anchors.topMargin: inputField.borderTop
      anchors.rightMargin: inputField.borderRight + 18 + root.fingerprintReserve
      anchors.bottomMargin: inputField.borderBottom
      anchors.leftMargin: inputField.borderLeft + 18 + root.fingerprintReserve
      verticalAlignment: TextInput.AlignVCenter
      horizontalAlignment: TextInput.AlignHCenter
      activeFocusOnPress: true
      clip: true
      enabled: root.inputEnabled && !root.authenticatingPassword
      readOnly: root.authenticatingPassword
      echoMode: TextInput.Password
      passwordCharacter: "\u25CF"
      passwordMaskDelay: 0
      color: root.foreground
      selectionColor: root.selectionColor
      selectedTextColor: root.foreground
      font.family: root.fontFamily
      font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
      font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
      cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
      cursorDelegate: Rectangle {
        width: 2
        color: root.foreground
        visible: passwordInput.cursorVisible
      }

      onTextChanged: {
        if (!root.syncingPasswordText)
          root.passwordTextEdited(text)
        if (text.length > 0)
          root.wakeRequested()
        if (text.length > 0 && root.failureMessage.length > 0)
          root.clearFailureRequested()
      }

      onAccepted: {
        var submitted = root.passwordText
        root.passwordTextEdited("")
        if (submitted.length > 0)
          root.submitPassword(submitted)
      }

      Keys.onPressed: function (event) {
        root.wakeRequested()
        if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
          root.passwordTextEdited("")
          event.accepted = true
        }
      }
    }

    Text {
      anchors.fill: passwordInput
      text: root.authenticatingPassword ? "Checking…" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
      visible: passwordInput.text.length === 0
      color: root.authenticatingPassword ? root.foreground : (root.failureMessage.length > 0 ? root.errorColor : root.placeholderColor)
      font.family: root.fontFamily
      font.pixelSize: root.fieldFontSize
      font.italic: !root.authenticatingPassword && root.failureMessage.length > 0
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }

    Text {
      id: fingerprintIcon
      objectName: "fingerprintIndicator"
      anchors.right: parent.right
      anchors.rightMargin: inputField.borderRight + 18
      anchors.verticalCenter: parent.verticalCenter
      visible: root.fingerprintConfigured
      text: "󰈷"
      color: root.placeholderColor
      font.family: root.fontFamily
      font.pixelSize: Math.round(root.fieldFontSize * 1.1)
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
  }
}
