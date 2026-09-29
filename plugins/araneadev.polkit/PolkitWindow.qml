// Window of the Aranea polkit prompt: the full-screen scrim with the card,
// request, details and password field. PolkitAgent.qml (the non-visual plugin
// entry, which holds all state and logic) creates it and passes itself as
// `root`; tests leave it out and use a fake view instead.
// qmllint disable missing-property

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "../araneadev.shared" as Aranea
import "PolkitLogic.js" as PolkitLogic

PanelWindow {
  id: panel

  // The polkit entry (PolkitAgent.qml) this window draws; set at creation.
  required property var root
  // Never wider than the screen (minus gaps), even on a very narrow one.
  readonly property int cardWidth: Math.max(Style.space(120), Math.min(Style.space(380), panel.width - Style.gapsOut * 2))

  // Returns the typed password.
  function passwordText(): string {
    return authField.passwordText
  }

  // Clears the typed password.
  function clearPassword(): void {
    authField.clearPassword()
  }

  // Gives the password field the keyboard focus.
  function focusField(): void {
    authField.focusField()
  }

  // Gives the key catcher the keyboard focus (fingerprint mode, after submit).
  function focusKeys(): void {
    keyCatcher.forceActiveFocus()
  }

  // Short shake for an empty Enter.
  function nudge(): void {
    nudgeAnimation.restart()
  }

  // Shake for a failed attempt.
  function shake(): void {
    shakeAnimation.restart()
  }

  // Entrance animation for a new request.
  function playOpen(): void {
    openAnimation.restart()
  }

  SequentialAnimation {
    id: shakeAnimation
    NumberAnimation {
      target: panel.root
      property: "shakeOffset"
      to: -8
      duration: 35
      easing.type: Easing.OutQuad
    }
    NumberAnimation {
      target: panel.root
      property: "shakeOffset"
      to: 8
      duration: 50
      easing.type: Easing.InOutQuad
    }
    NumberAnimation {
      target: panel.root
      property: "shakeOffset"
      to: 0
      duration: 55
      easing.type: Easing.OutQuad
    }
  }
  // Gentler, slower shake than the failure shake, for an empty Enter (~200 ms).
  SequentialAnimation {
    id: nudgeAnimation
    NumberAnimation {
      target: panel.root
      property: "shakeOffset"
      to: -4
      duration: 50
      easing.type: Easing.OutQuad
    }
    NumberAnimation {
      target: panel.root
      property: "shakeOffset"
      to: 4
      duration: 70
      easing.type: Easing.InOutQuad
    }
    NumberAnimation {
      target: panel.root
      property: "shakeOffset"
      to: 0
      duration: 80
      easing.type: Easing.OutQuad
    }
  }
  ParallelAnimation {
    id: openAnimation
    NumberAnimation {
      target: scrimRect
      property: "opacity"
      from: 0
      to: 1
      duration: 160
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: card
      property: "opacity"
      from: 0
      to: 1
      duration: 180
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: card
      property: "scale"
      from: 0.97
      to: 1
      duration: 180
      easing.type: Easing.OutCubic
    }
  }

  visible: panel.root.dialogVisible
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: "transparent"
  WlrLayershell.namespace: "omarchy-polkit"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore

  Rectangle {
    id: scrimRect
    anchors.fill: parent
    color: panel.root.scrim
  }

  MouseArea {
    anchors.fill: parent
    onClicked: panel.root.refocus()
  }

  Aranea.SurfaceCard {
    id: card
    width: panel.cardWidth
    height: Math.min(content.implicitHeight + card.contentTopInset + card.contentBottomInset, panel.height - Style.gapsOut * 2)
    cornerRadius: panel.root.cornerRadius
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: panel.root.shakeOffset
    fillColor: panel.root.background
    borderSpecOverride: panel.root.borderSpec
    contentPadding: panel.root.contentMargin
    clipContent: true  // content never spills past the card on very short screens
    clip: true

    MouseArea {
      anchors.fill: parent
      onClicked: panel.root.refocus()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function (event) {
        panel.root.handleKey(event)
      }
    }

    ColumnLayout {
      id: content
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.topMargin: card.contentTopInset
      anchors.leftMargin: card.contentLeftInset
      anchors.rightMargin: card.contentRightInset
      spacing: Style.space(10)

      PolkitPromptCard {
        Layout.fillWidth: true
        currentMessage: panel.root.currentMessage
        currentPrompt: panel.root.currentPrompt
        identityText: panel.root.identityText
        identityCount: panel.root.identityCount
        targetText: panel.root.targetText
        actionDescription: panel.root.actionDescription
        currentActionId: panel.root.currentActionId
        actionVendor: panel.root.actionVendor
        detailsOpen: panel.root.detailsOpen
        glyphSource: panel.root.glyphSource
        fontFamily: panel.root.fontFamily
        foreground: panel.root.foreground
        dim: panel.root.dim
        accent: panel.root.accent
        letterSpacing: panel.root.letterSpacing
        onDetailsToggled: panel.root.toggleDetails()
        onKeyPressed: function (event) {
          panel.root.handleKey(event)
        }
      }

      // Password field (or the sensor in fingerprint mode).
      PolkitAuthField {
        id: authField
        fingerprintMode: panel.root.fingerprintMode
        fieldHeight: panel.root.fieldHeight
        cornerRadius: panel.root.cornerRadius
        foreground: panel.root.foreground
        accent: panel.root.accent
        errorColor: Color.polkit.textError
        errorFlash: panel.root.errorFlash
        responseVisible: panel.root.responseVisible
        submitted: panel.root.submitted
        dialogVisible: panel.root.dialogVisible
        currentPrompt: panel.root.currentPrompt
        placeholderText: PolkitLogic.promptPlaceholder(panel.root.currentPrompt)
        fontFamily: panel.root.fontFamily
        letterSpacing: panel.root.letterSpacing
        onKeyPressed: function (event) {
          panel.root.handleKey(event)
        }
      }

      // PAM's own messages ("Sorry, try again", fingerprint hints).
      Text {
        Layout.fillWidth: true
        visible: panel.root.currentSupplementary.length > 0
        textFormat: Text.PlainText
        text: panel.root.currentSupplementary
        color: panel.root.supplementaryIsError ? Color.polkit.textError : panel.root.dim
        font.family: panel.root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Util.alpha(panel.root.foreground, 0.10)
      }

      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: panel.root.hintText
        color: panel.root.dim
        font.family: panel.root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        font.letterSpacing: panel.root.letterSpacing
        elide: Text.ElideRight
      }
    }
  }
}
