// Window of the Aranea polkit prompt: the full-screen scrim with the card,
// request, details and password field. PolkitAgent.qml (the non-visual plugin
// entry, which holds all state and logic) creates it and passes itself as
// `root`; tests leave it out and use a fake view instead.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
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
    return passwordInput.text
  }

  // Clears the typed password.
  function clearPassword(): void {
    passwordInput.text = ""
  }

  // Gives the password field the keyboard focus.
  function focusField(): void {
    passwordInput.forceActiveFocus()
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

      // Header: the mark says this is the system asking.
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(10)

        Image {
          Layout.preferredWidth: Style.space(22)
          Layout.preferredHeight: Style.space(22)
          source: panel.root.glyphSource
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
            color: panel.root.foreground
            font.family: panel.root.fontFamily
            font.pixelSize: Style.font.title
            font.weight: Font.Medium
            font.letterSpacing: panel.root.letterSpacing
            elide: Text.ElideRight
          }
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: "SYSTEM // PRIVILEGED"
            color: panel.root.dim
            font.family: panel.root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.Medium
            font.letterSpacing: panel.root.letterSpacing
            elide: Text.ElideRight
          }
        }
      }

      // The request, command in the accent colour (polkit text escaped).
      Text {
        id: requestLine
        Layout.fillWidth: true
        textFormat: Text.StyledText
        text: PolkitLogic.requestMarkup(panel.root.currentMessage, panel.root.accent.toString())
        color: panel.root.foreground
        font.family: panel.root.fontFamily
        font.pixelSize: Style.font.subtitle
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }

      // The target, never elided: who the command runs as always shows in full.
      Text {
        Layout.fillWidth: true
        visible: text.length > 0
        textFormat: Text.PlainText
        text: panel.root.targetText
        color: panel.root.accent
        font.family: panel.root.fontFamily
        font.pixelSize: requestLine.font.pixelSize
        wrapMode: Text.Wrap
      }

      // What polkit says the action is, and who is authenticating.
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: PolkitLogic.contextLine(panel.root.actionDescription, panel.root.identityText, panel.root.identityCount)
          color: panel.root.dim
          font.family: panel.root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
        Text {
          textFormat: Text.PlainText
          text: (panel.root.detailsOpen ? "▴" : "▾") + " DETAILS"
          color: panel.root.accent
          font.family: panel.root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.Medium
          font.letterSpacing: panel.root.letterSpacing
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.root.toggleDetails()
          }
        }
      }

      // Details: raw polkit data, selectable, hidden rows when empty.
      ColumnLayout {
        Layout.fillWidth: true
        visible: panel.root.detailsOpen
        spacing: Style.space(4)
        Repeater {
          model: PolkitLogic.detailRows(panel.root.currentActionId, panel.root.actionVendor, PolkitLogic.commandFromMessage(panel.root.currentMessage), panel.root.currentMessage)
          delegate: RowLayout {
            id: detailRow
            required property var modelData
            Layout.fillWidth: true
            spacing: Style.space(10)
            Text {
              Layout.preferredWidth: Style.space(64)
              Layout.alignment: Qt.AlignTop
              textFormat: Text.PlainText
              text: detailRow.modelData.key
              color: panel.root.dim
              font.family: panel.root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.Medium
              font.letterSpacing: panel.root.letterSpacing
            }
            TextEdit {
              Layout.fillWidth: true
              textFormat: TextEdit.PlainText
              text: detailRow.modelData.value
              readOnly: true
              selectByMouse: true
              activeFocusOnPress: false
              wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
              color: panel.root.foreground
              selectionColor: Util.alpha(panel.root.accent, 0.45)
              selectedTextColor: panel.root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function (event) {
                panel.root.handleKey(event)
              }
            }
          }
        }
      }

      // Password field (or the sensor in fingerprint mode).
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: panel.root.fieldHeight
        radius: panel.root.cornerRadius
        color: Util.alpha(panel.root.foreground, 0.04)
        border.width: 1
        border.color: panel.root.errorFlash ? Color.polkit.textError : Util.alpha(panel.root.foreground, passwordInput.activeFocus ? 0.22 : 0.10)

        Row {
          visible: panel.root.fingerprintMode
          anchors.centerIn: parent
          spacing: Style.space(10)
          OpticalGlyph {
            width: Math.round(panel.root.fieldHeight * 0.55)
            height: width
            text: "󰈷"
            fontFamily: panel.root.fontFamily
            fontSize: Math.round(panel.root.fieldHeight * 0.55)
            color: panel.root.errorFlash ? Color.polkit.textError : panel.root.accent
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "TOUCH THE SENSOR"
            color: panel.root.foreground
            font.family: panel.root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.Medium
            font.letterSpacing: panel.root.letterSpacing
          }
        }

        Row {
          visible: !panel.root.fingerprintMode
          anchors.fill: parent
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(10)

          Text {
            text: ""
            color: panel.root.errorFlash ? Color.polkit.textError : panel.root.accent
            font.family: panel.root.fontFamily
            font.pixelSize: Style.font.iconLarge
            width: Style.space(20)
            height: panel.root.fieldHeight
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }

          Item {
            width: parent.width - Style.space(30)
            height: panel.root.fieldHeight

            TextInput {
              id: passwordInput
              anchors.fill: parent
              verticalAlignment: TextInput.AlignVCenter
              activeFocusOnPress: true
              clip: true
              selectionColor: Util.alpha(panel.root.accent, 0.45)
              selectedTextColor: panel.root.foreground
              font.family: panel.root.fontFamily
              font.pixelSize: Style.font.iconLarge
              echoMode: panel.root.responseVisible ? TextInput.Normal : TextInput.Password
              passwordCharacter: "•"
              color: panel.root.errorFlash ? Color.polkit.textError : panel.root.foreground
              cursorVisible: activeFocus && !panel.root.submitted && !panel.root.errorFlash
              readOnly: panel.root.submitted || panel.root.errorFlash
              enabled: panel.root.dialogVisible
              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function (event) {
                panel.root.handleKey(event)
              }
            }

            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: panel.root.errorFlash ? "Wrong" : (panel.root.submitted ? "Checking..." : PolkitLogic.promptPlaceholder(panel.root.currentPrompt))
              color: panel.root.errorFlash ? Color.polkit.textError : panel.root.foreground
              opacity: panel.root.errorFlash ? 1 : 0.36
              font.family: panel.root.fontFamily
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
