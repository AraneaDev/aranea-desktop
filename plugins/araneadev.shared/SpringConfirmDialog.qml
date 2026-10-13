// Owned adaptation of /usr/share/omarchy/shell/Ui/ConfirmDialog.qml.
// Preserves its destructive selection, layout and key protocol.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  // Host-owned logical state that immediately gates confirmation input.
  property bool opened: false
  // Presentation policy is shared; logical ownership stays with the host.
  property bool motionEnabled: MotionState.motionEnabled
  // Plain text prompt wrapped within the confirmation card.
  property string message: ""
  // Label for the non-destructive cancellation action.
  property string cancelText: "Cancel"
  // Label for the destructive confirmation action.
  property string confirmText: "Confirm"
  // Keyboard selection, with index one matching the upstream default.
  property int selectedIndex: 1
  // Confirmation card fill supplied by the host palette.
  property color background: Color.background
  // Prompt and unselected action text color.
  property color foreground: Color.foreground
  // Dimmed backdrop behind the centered card.
  property color scrim: Util.alpha(Color.background, 0.7)
  // Fill used by the selected cancellation action.
  property color selectedBackground: Util.alpha(Color.foreground, 0.08)
  // Accent used by the selected cancellation action and card border.
  property color selectedText: Color.accent
  // Dynamic upstream font sizes and family.
  readonly property var fontStyle: Style.font
  // Font family shared by prompt and action labels.
  property string fontFamily: fontStyle.family
  // Confirmation card corner radius.
  property int cornerRadius: Style.cornerRadius

  // Requests cancellation; the host remains responsible for closing.
  signal canceled
  // Requests the selected destructive action; the host owns execution.
  signal confirmed

  // Handles upstream cancel, selection and activation keys only while open.
  function handleKey(event) {
    if (!root.opened)
      return false

    if (event.key === Qt.Key_Escape) {
      root.canceled()
      return true
    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      root.selectedIndex = root.selectedIndex === 0 ? 1 : 0
      return true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (root.selectedIndex === 0)
        root.canceled()
      else
        root.confirmed()
      return true
    }

    return false
  }

  visible: motion.present
  enabled: opened

  SurfaceMotion {
    id: motion
    opened: root.opened
    motionEnabled: root.motionEnabled
  }

  Rectangle {
    anchors.fill: parent
    color: "transparent"

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      opacity: motion.opacity
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.canceled()
    }

    BorderSurface {
      id: card
      objectName: "springConfirmationCard"
      scale: motion.scale
      opacity: motion.opacity
      width: Math.min(parent.width - Style.space(32), Style.space(370))
      // Grows with the wrapped message so narrow hosts (like the menu card)
      // don't squeeze the text into the buttons.
      height: card.contentTopInset + card.contentBottomInset + messageText.implicitHeight + Style.space(20) + Style.space(34)
      anchors.centerIn: parent
      color: root.background
      borderSpec: Border.flat(Util.alpha(root.foreground, 0.16), Style.normalBorderWidth)
      padding: Style.space(18)
      radius: root.cornerRadius

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Text {
          id: messageText
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          text: root.message
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: root.fontStyle.title
          wrapMode: Text.WordWrap
        }

        Row {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.space(10)

          Repeater {
            model: [root.cancelText, root.confirmText]

            BorderSurface {
              id: action
              required property int index
              required property string modelData

              readonly property bool selected: root.selectedIndex === index
              readonly property bool destructive: index === 1

              width: Style.space(88)
              height: Style.space(34)
              color: selected ? (destructive ? Util.alpha(Color.urgent, 0.22) : root.selectedBackground) : "transparent"
              borderSpec: Border.flat(destructive ? (selected ? Color.urgent : Util.alpha(Color.urgent, 0.56)) : Util.alpha(root.foreground, selected ? 0.22 : 0.14), Style.normalBorderWidth)
              radius: 0

              FocusFrame {
                anchors.fill: parent
                focused: action.selected && !action.destructive
              }

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: action.modelData
                color: action.destructive ? (action.selected ? Color.urgent : root.foreground) : (action.selected ? root.selectedText : root.foreground)
                font.family: root.fontFamily
                font.pixelSize: root.fontStyle.caption
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = action.index
                onClicked: {
                  if (action.index === 0)
                    root.canceled()
                  else
                    root.confirmed()
                }
              }
            }
          }
        }
      }
    }
  }
}
