// Inline credential prompt in the Filament style, shared by the Network
// passphrase prompt and the VPN password / 2FA prompt: a thin accent-to-
// violet frame around one line per field (a text field, or a read-only
// label and value), with a check-glyph connect button beside the last
// editable field. Opening it focuses the first editable field; Enter moves
// to the next editable field and submits on the last; Esc cancels. While
// busy or failed, a message takes the fields' place.
//
// The field Repeater's model is the field count, so a host rebuilding
// `fields` on every keystroke (to echo the typed values back) never
// rebuilds a field and never drops a half-typed secret or its selection.
// With a pointerGate, a connect click within settleMs of the prompt
// opening is ignored unless the pointer has really moved over it since,
// so a prompt opening under a still pointer can't be clicked by accident.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: prompt

  // The fields, in order: [{key, label, placeholder, secret, readOnly,
  // optional, hidden, value}]. A secret field echoes as a password; a
  // read-only one shows its label and value (or its placeholder when the
  // value is empty); a hidden one is left out but kept, so toggling it never
  // rebuilds the others; connect needs every shown editable field that
  // isn't optional filled. Each field is objectName key + "Field" (a
  // read-only one's label key + "Label").
  property var fields: []
  // Whether the connect is running: busyText replaces the fields.
  property bool busy: false
  // The busy message.
  property string busyText: "Connecting..."
  // Whether the connect failed: failedText, urgent, replaces the fields.
  property bool failed: false
  // The failure message.
  property string failedText: "Wrong password"
  // Optional PointerMoveGate (qs.Ui): with one, the connect button ignores
  // a click within settleMs of opening unless the pointer has moved here.
  property var pointerGate: null
  // How long after opening a connect click is ignored, in ms (with a gate).
  property int settleMs: 300
  // When the prompt last opened (Date.now()), for settleMs.
  property real openedAt: 0
  // Whether the gate has accepted a real pointer move over the prompt since
  // it opened.
  property bool pointerMovedHere: false
  // What each field holds now, by key, so connect enables as you type.
  property var texts: ({})
  // Each field's text input, by index, registered by the field slots.
  property var inputs: ({})
  // Whether a message shows instead of the fields.
  readonly property bool message: prompt.busy || prompt.failed
  // The last editable field's index (where the connect button sits), or -1.
  readonly property int lastEditable: prompt.editableFrom(prompt.fields.length - 1, -1)
  // Whether every required field holds something.
  readonly property bool complete: (prompt.fields || []).every(function (f) {
    return !f || f.readOnly || f.optional || f.hidden || (prompt.texts[f.key] || "").length > 0
  })

  // Emitted on Enter in the last editable field.
  signal submit
  // Emitted on Esc in any field.
  signal cancel
  // Emitted when field KEY's text changes to TEXT by typing.
  signal edited(string key, string text)
  // Emitted when the connect button is clicked (a pointer action).
  signal connectClicked

  // The first shown editable field's index from FROM, stepping by STEP (1
  // or -1), or -1 when there's none.
  function editableFrom(from, step) {
    var list = prompt.fields || []
    for (var i = from; i >= 0 && i < list.length; i += step)
      if (list[i] && !list[i].readOnly && !list[i].hidden)
        return i
    return -1
  }

  // The text input of field INDEX, or null.
  function inputAt(index) {
    return prompt.inputs[index] || null
  }

  // Focuses the first editable field, while open and showing the fields.
  function focusFirst() {
    if (!prompt.visible || prompt.message)
      return
    var input = prompt.inputAt(prompt.editableFrom(0, 1))
    if (input)
      input.forceActiveFocus()
  }

  // Enter in field INDEX: focus the next editable field, or submit.
  function advance(index) {
    var next = prompt.editableFrom(index + 1, 1)
    if (next < 0)
      prompt.submit()
    else
      prompt.inputAt(next).forceActiveFocus()
  }

  // Records TEXT as field KEY's current text.
  function noteText(key, text) {
    var copy = {}
    for (var k in prompt.texts)
      copy[k] = prompt.texts[k]
    copy[key] = text
    prompt.texts = copy
  }

  // Whether a connect click counts: no gate, or settled since opening.
  function clickSettled() {
    return !prompt.pointerGate || prompt.pointerMovedHere || Date.now() - prompt.openedAt >= prompt.settleMs
  }

  objectName: "promptPanel"
  height: visible ? content.implicitHeight + Style.space(16) : 0
  onVisibleChanged: if (visible) {
    prompt.openedAt = Date.now()
    prompt.pointerMovedHere = false
    Qt.callLater(prompt.focusFirst)
  }
  onMessageChanged: if (!prompt.message)
    Qt.callLater(prompt.focusFirst)
  Component.onCompleted: {
    prompt.openedAt = Date.now()
    if (prompt.visible)
      Qt.callLater(prompt.focusFirst)
  }

  Rectangle {
    anchors.top: parent.top
    width: parent.width
    height: 1
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop {
        position: 0
        color: DesignTokens.accent
      }
      GradientStop {
        position: 1
        color: DesignTokens.strandEnd
      }
    }
  }
  Rectangle {
    anchors.bottom: parent.bottom
    width: parent.width
    height: 1
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop {
        position: 0
        color: DesignTokens.accent
      }
      GradientStop {
        position: 1
        color: DesignTokens.strandEnd
      }
    }
  }
  Rectangle {
    anchors.left: parent.left
    width: 1
    height: parent.height
    color: DesignTokens.accent
  }
  Rectangle {
    anchors.right: parent.right
    width: 1
    height: parent.height
    color: DesignTokens.strandEnd
  }
  Column {
    id: content
    x: Style.space(8)
    y: Style.space(8)
    width: parent.width - Style.space(16)
    spacing: Style.space(4)

    Column {
      width: content.width
      visible: !prompt.message
      spacing: Style.space(4)

      Repeater {
        id: repeater
        model: prompt.fields ? prompt.fields.length : 0

        Item {
          id: slot
          required property int index
          // This slot's field.
          readonly property var field: (prompt.fields || [])[slot.index] || ({})
          // Whether the field takes typing.
          readonly property bool editable: !slot.field.readOnly
          // Whether the connect button sits beside this field.
          readonly property bool last: slot.index === prompt.lastEditable

          width: content.width
          visible: !slot.field.hidden
          height: slot.editable ? Math.max(input.implicitHeight, connect.visible ? connect.implicitHeight : 0) : Math.max(fieldLabel.implicitHeight, readOnlyValue.implicitHeight)
          Component.onCompleted: {
            prompt.inputs[slot.index] = input
            prompt.noteText(slot.field.key || "", input.text)
            if (prompt.visible)
              Qt.callLater(prompt.focusFirst)
          }
          Component.onDestruction: if (prompt.inputs[slot.index] === input)
            delete prompt.inputs[slot.index]

          TextField {
            id: input
            objectName: slot.editable ? (slot.field.key || "") + "Field" : ""
            anchors.left: parent.left
            anchors.right: connect.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            visible: slot.editable
            password: !!slot.field.secret
            placeholderText: slot.field.placeholder || ""
            foreground: DesignTokens.foreground
            accent: DesignTokens.accent
            horizontalPadding: Style.spacing.controlGap
            verticalPadding: Style.spacing.controlPaddingY
            text: slot.field.value || ""
            onAccepted: prompt.advance(slot.index)
            onTextChanged: {
              prompt.noteText(slot.field.key || "", text)
              if (prompt.visible && slot.editable && text !== (slot.field.value || ""))
                prompt.edited(slot.field.key || "", text)
            }
            Keys.onEscapePressed: prompt.cancel()
          }
          PanelActionButton {
            id: connect
            objectName: slot.last ? "connectButton" : ""
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: slot.last
            enabled: prompt.complete
            iconText: String.fromCodePoint(0xf012c)
            tooltipText: "Connect"
            foreground: DesignTokens.foreground
            hoverColor: DesignTokens.accent
            onClicked: if (prompt.clickSettled())
              prompt.connectClicked()
          }
          Text {
            id: fieldLabel
            objectName: slot.editable ? "" : (slot.field.key || "") + "Label"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: !slot.editable && (slot.field.value || "") !== ""
            text: slot.field.label || ""
            color: Util.alpha(DesignTokens.foreground, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Text {
            id: readOnlyValue
            objectName: slot.editable ? "" : (slot.field.key || "") + "Field"
            anchors.left: fieldLabel.visible ? fieldLabel.right : parent.left
            anchors.leftMargin: fieldLabel.visible ? Style.space(10) : 0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !slot.editable
            text: (slot.field.value || "") !== "" ? slot.field.value : (slot.field.placeholder || "")
            elide: Text.ElideRight
            color: (slot.field.value || "") !== "" ? Util.alpha(DesignTokens.foreground, 0.82) : Util.alpha(DesignTokens.foreground, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
    Text {
      objectName: "promptStatus"
      width: content.width
      visible: prompt.message
      horizontalAlignment: Text.AlignHCenter
      text: prompt.failed ? prompt.failedText : prompt.busyText
      color: prompt.failed ? DesignTokens.urgent : DesignTokens.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
  HoverHandler {
    id: hover
    onPointChanged: if (prompt.pointerGate && hover.hovered && prompt.pointerGate.moved(prompt, {
      x: hover.point.position.x,
      y: hover.point.position.y
    }))
      prompt.pointerMovedHere = true
  }
}
