// Aranea lock screen view: blurred wallpaper, spider logo, password field,
// clock and hint line. Purely presentational; all state comes in through
// properties and user actions go out through signals. Instantiated by
// Service.qml twice: inside the WlSessionLockSurface (the real lock) and in
// the preview PanelWindow (input disabled).
import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons

Item {
  id: root

  // Absolute path of the wallpaper to show behind the lock (empty for none).
  property string backgroundPath: ""
  // Bumped by the service when the wallpaper changes; appended to image URLs to force a reload.
  property int backgroundVersion: 0
  // True when a fingerprint is enrolled: shows the fingerprint icon and changes the hint text.
  property bool fingerprintConfigured: false
  // True while PAM checks a password: shows "Checking..." and makes the field read-only.
  property bool authenticatingPassword: false
  // Last authentication error; shown as the placeholder and switches the border to the error colour.
  property string failureMessage: ""
  // Whether the password field accepts input; focus is forced into it whenever this turns true.
  property bool inputEnabled: true
  // Whether to load and blur the wallpaper at all; false leaves the plain background colour.
  property bool loadBackground: true
  // Password text owned by the service; copied into the field whenever it changes.
  property string passwordText: ""
  // Set while syncPasswordText() writes the field, so the resulting edit is not echoed back.
  property bool syncingPasswordText: false
  // Current time as HH:mm, refreshed every second by updateClock().
  property string clockText: ""
  // Current date (weekday, day, month), refreshed with the clock so a lock
  // left up past midnight shows the right day.
  property string dateText: ""

  // Placeholder shown in the empty field when nothing else needs saying.
  readonly property string placeholderText: "Enter Password"
  // Omarchy's fixed state path (~/.local/state; Omarchy ignores the XDG
  // state variable), the same root Service.qml uses.
  readonly property string stateHome: Quickshell.env("HOME") + "/.local/state"
  // Directory of the active Omarchy theme; the spider logo (unlock.png) is loaded from here.
  readonly property string themeAssetRoot: stateHome + "/omarchy/current/theme"
  // Password field width in pixels.
  readonly property int fieldWidth: 381
  // Password field height in pixels.
  readonly property int fieldHeight: 67
  // Password field border thickness in pixels.
  readonly property int outlineThickness: 3
  // Font size of the placeholder and messages in the field.
  readonly property int fieldFontSize: Math.round(Style.font.heading * 1.125)
  // Full-size font size of the password dots, before passwordDotScale shrinks them.
  readonly property int passwordDotFontSize: Math.round(Style.font.heading * 1.33)
  // Full-size letter spacing between password dots.
  readonly property int passwordDotLetterSpacing: Math.round(Style.font.heading * 0.19)
  // Space to keep clear on each side of the field for the fingerprint icon
  // (icon width plus a gap) so the centered dots never run under it.
  readonly property real fingerprintReserve: authPanel.fingerprintReserve
  // Shrink the dots to fit once the password outgrows the field, so every
  // keystroke stays visible; otherwise long passwords clip with no feedback.
  readonly property real passwordDotScale: authPanel.passwordDotScale
  // Whether the text cursor may show: input enabled, no check running and no error shown.
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  // True while a failure message is shown.
  readonly property bool errorState: failureMessage.length > 0
  // Border spec for the field: the lock surface's error border in errorState, its active border otherwise.
  readonly property var inputBorderSpec: errorState ? Border.surfaceSpec("lock", "border-error", Color.lock.borderError, root.outlineThickness, "border-alpha") : Border.surfaceSpec("lock", "border-active", Color.lock.borderActive, root.outlineThickness, "border-alpha")

  // Emitted on Enter with the typed password (only when it is non-empty).
  signal submitPassword(string password)
  // Emitted when the user edits the field, or with "" to clear it (Enter, Escape, Ctrl+U).
  signal passwordTextEdited(string password)
  // Emitted when the user starts typing while a failure message is shown.
  signal clearFailureRequested
  // Emitted on pointer movement, clicks, key presses and typing so the service can wake the display.
  signal wakeRequested

  // Cache-busts the lock background by appending `?v=`. Adding a query
  // string keeps Image's loader happy while forcing it to reload when the
  // user picks a new background mid-session.
  function fileUrl(path: string): string {
    if (!path)
      return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + backgroundVersion
  }

  // Gives keyboard focus to the password field.
  function forcePasswordFocus() {
    authPanel.forcePasswordFocus()
  }

  // Copies passwordText into the field if they differ, flagging the write so it is not re-emitted.
  function syncPasswordText() {
    authPanel.syncPasswordText()
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled)
      Qt.callLater(forcePasswordFocus)
  }
  Component.onCompleted: {
    syncPasswordText()
    updateClock()
    if (inputEnabled)
      Qt.callLater(forcePasswordFocus)
  }

  // Sets clockText (HH:mm) and dateText to now.
  function updateClock(): void {
    var now = new Date()
    clockText = Qt.formatDateTime(now, "HH:mm")
    dateText = Qt.formatDate(now, "dddd  •  dd MMMM")
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.updateClock()
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background

    Image {
      id: wallpaper
      anchors.fill: parent
      source: root.loadBackground ? root.fileUrl(root.backgroundPath) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
    }

    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper
      autoPaddingEnabled: false
      blurEnabled: root.loadBackground && wallpaper.status === Image.Ready
      blur: 0.45
      blurMax: 72
      blurMultiplier: 1.0
      contrast: -0.04
    }

    Rectangle {
      anchors.fill: parent
      color: "#a006090d"
    }

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop {
          position: 0.0
          color: "#4406090d"
        }
        GradientStop {
          position: 0.48
          color: "#1806090d"
        }
        GradientStop {
          position: 1.0
          color: "#7006090d"
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: {
        root.wakeRequested()
        root.forcePasswordFocus()
      }
      onPositionChanged: root.wakeRequested()
    }

    LockAuthPanel {
      id: authPanel
      width: root.fieldWidth
      height: root.fieldHeight
      anchors.centerIn: parent
      anchors.verticalCenterOffset: Math.min(130, parent.height * 0.12)
      passwordText: root.passwordText
      syncingPasswordText: root.syncingPasswordText
      inputEnabled: root.inputEnabled
      authenticatingPassword: root.authenticatingPassword
      fingerprintConfigured: root.fingerprintConfigured
      failureMessage: root.failureMessage
      placeholderText: root.placeholderText
      fieldWidth: root.fieldWidth
      fieldHeight: root.fieldHeight
      fieldFontSize: root.fieldFontSize
      passwordDotFontSize: root.passwordDotFontSize
      passwordDotLetterSpacing: root.passwordDotLetterSpacing
      inputBorderSpec: root.inputBorderSpec
      cornerRadius: Math.max(10, Style.space(10))
      fontFamily: Style.font.family
      foreground: Color.lock.text
      placeholderColor: Color.lock.placeholder
      errorColor: Color.lock.textError
      selectionColor: Color.lock.selection
      onSubmitPassword: function (password) {
        root.submitPassword(password)
      }
      onPasswordTextEdited: function (password) {
        root.passwordTextEdited(password)
      }
      onClearFailureRequested: root.clearFailureRequested()
      onWakeRequested: root.wakeRequested()
    }

    LockBranding {
      width: parent.width
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.max(32, authPanel.y - height - 42)
      z: 1
      logoSource: root.fileUrl(root.themeAssetRoot + "/unlock.png")
      fontFamily: Style.font.family
      textColor: Color.lock.text
      placeholderColor: Color.lock.placeholder
    }

    LockClock {
      anchors.horizontalCenter: parent.horizontalCenter
      y: authPanel.y + authPanel.height + 28
      z: 1
      clockText: root.clockText
      dateText: root.dateText
      fontFamily: Style.font.family
      textColor: Color.lock.text
      placeholderColor: Color.lock.placeholder
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height - height - 34
      text: root.fingerprintConfigured ? "TOUCH SENSOR OR ENTER PASSWORD" : "ENTER PASSWORD TO CONTINUE"
      color: Color.lock.placeholder
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.letterSpacing: 1.5
      z: 1
    }
  }
}
