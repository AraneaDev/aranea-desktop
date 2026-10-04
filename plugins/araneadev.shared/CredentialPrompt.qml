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
// opening, or of its dropdown's layout shifting
// (pointerGate.layoutChangedAt), is ignored unless the pointer has really
// moved over it since, so a prompt opening or sliding under a still
// pointer can't be clicked by accident.
//
// The Polkit prompt uses it inline (inlineStatus): busy and failed then
// show on the field itself instead of replacing it. Busy pulses the frame
// and fields and makes them read-only; failed turns the frame and glyph
// urgent, shows failedText as the placeholder and makes them read-only.
// It also hides the connect button (connectShown), gives its field a
// leading glyph (a field's `glyph`) and takes keys the prompt leaves alone
// (Tab, Shift+Tab) through unhandledKey.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "ClickSettle.js" as ClickSettle

Item {
  id: prompt

  // The fields, in order: [{key, label, placeholder, secret, readOnly,
  // optional, hidden, value, glyph}]. A secret field echoes as a password; a
  // read-only one shows its label and value (or its placeholder when the
  // value is empty); a hidden one is left out but kept, so toggling it never
  // rebuilds the others; connect needs every shown editable field that
  // isn't optional filled; a glyph shows before the field. Each field is
  // objectName key + "Field" (a read-only one's label key + "Label", a
  // glyph key + "Glyph").
  property var fields: []
  // Whether the connect is running: busyText replaces the fields.
  property bool busy: false
  // The busy message.
  property string busyText: "Connecting…"
  // Whether the connect failed: failedText, urgent, replaces the fields.
  property bool failed: false
  // The failure message.
  property string failedText: "Wrong password"
  // Whether busy and failed show on the fields (pulse, urgent placeholder,
  // read-only) instead of replacing them with a message.
  property bool inlineStatus: false
  // Whether the connect button shows beside the last editable field.
  property bool connectShown: true
  // Accent of the frame, field focus and glyphs (DesignTokens by default).
  property color accentColor: DesignTokens.accent
  // Text colour of the fields (DesignTokens by default).
  property color foregroundColor: DesignTokens.foreground
  // Colour of a failure (DesignTokens by default).
  property color urgentColor: DesignTokens.urgent
  // Opacity the inline busy pulse drives, 0.45..1.
  property real pulseOpacity: 1
  // Optional PointerMoveGate (qs.Ui): with one, the connect button ignores
  // a click within settleMs of opening or of a layout shift unless the
  // pointer has moved here since.
  property var pointerGate: null
  // How long after opening or a layout shift a connect click is ignored,
  // in ms (with a gate).
  property int settleMs: 300
  // When the prompt last opened (Date.now()), for settleMs.
  property real openedAt: 0
  // When the gate last accepted a real pointer move over the prompt
  // (Date.now()), 0 for never; reset when it opens.
  property real pointerMovedAt: 0
  // What each field holds now, by key, so connect enables as you type.
  property var texts: ({})
  // Each field's text input, by index, registered by the field slots.
  property var inputs: ({})
  // Whether a message shows instead of the fields.
  readonly property bool message: !prompt.inlineStatus && (prompt.busy || prompt.failed)
  // Whether the inline busy or failed state holds the fields read-only.
  readonly property bool locked: prompt.inlineStatus && (prompt.busy || prompt.failed)
  // Whether the inline failure shows on the fields.
  readonly property bool failedInline: prompt.inlineStatus && prompt.failed
  // Opacity of the frame and fields: the pulse while busy inline (static
  // 0.7 when motion is disabled), else 1.
  readonly property real statusOpacity: prompt.inlineStatus && prompt.busy && !prompt.failed ? (DesignTokens.motionEnabled ? prompt.pulseOpacity : 0.7) : 1
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
  // A key press in a field other than Enter and Esc (Tab, Shift+Tab,
  // typing); a handler sets event.accepted to take it from the field.
  signal unhandledKey(var event)

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

  // Enter in field INDEX: focus the next editable field, or submit. A next
  // field whose slot hasn't registered its input yet is left alone.
  function advance(index) {
    var next = prompt.editableFrom(index + 1, 1)
    if (next < 0) {
      prompt.submit()
      return
    }
    var input = prompt.inputAt(next)
    if (input)
      input.forceActiveFocus()
  }

  // Empties every editable field and forgets every recorded text, so no
  // typed secret outlives the clear (a field gone since keeps none either).
  function clearFields() {
    for (var i in prompt.inputs)
      if (prompt.inputs[i])
        prompt.inputs[i].text = ""
    prompt.texts = ({})
  }

  // Whether KEY names one of the current fields.
  function hasField(key) {
    var list = prompt.fields || []
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].key === key)
        return true
    return false
  }

  // Forgets the recorded text of every field no longer shown (a field
  // slot went away, or the fields were rebuilt with other keys).
  function pruneTexts() {
    var copy = {}
    var dropped = false
    for (var k in prompt.texts) {
      if (prompt.hasField(k))
        copy[k] = prompt.texts[k]
      else
        dropped = true
    }
    if (dropped)
      prompt.texts = copy
  }

  // Records TEXT as field KEY's current text.
  function noteText(key, text) {
    var copy = {}
    for (var k in prompt.texts)
      if (prompt.hasField(k))
        copy[k] = prompt.texts[k]
    copy[key] = text
    prompt.texts = copy
  }

  // Whether a connect click counts: no gate, or settled since opening and
  // since the last layout shift (ClickSettle.clickSettled).
  function clickSettled() {
    if (!prompt.pointerGate)
      return true
    return ClickSettle.clickSettled({
      now: Date.now(),
      createdAt: prompt.openedAt,
      movedAt: prompt.pointerMovedAt,
      layoutChangedAt: Number(prompt.pointerGate.layoutChangedAt) || 0,
      settleMs: prompt.settleMs
    })
  }

  objectName: "promptPanel"
  onFieldsChanged: prompt.pruneTexts()
  height: visible ? content.implicitHeight + Style.space(16) : 0
  onVisibleChanged: if (visible) {
    prompt.openedAt = Date.now()
    prompt.pointerMovedAt = 0
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
    opacity: prompt.statusOpacity
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop {
        position: 0
        color: prompt.failedInline ? prompt.urgentColor : prompt.accentColor
      }
      GradientStop {
        position: 1
        color: prompt.failedInline ? prompt.urgentColor : DesignTokens.strandEnd
      }
    }
  }
  Rectangle {
    anchors.bottom: parent.bottom
    width: parent.width
    height: 1
    opacity: prompt.statusOpacity
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop {
        position: 0
        color: prompt.failedInline ? prompt.urgentColor : prompt.accentColor
      }
      GradientStop {
        position: 1
        color: prompt.failedInline ? prompt.urgentColor : DesignTokens.strandEnd
      }
    }
  }
  Rectangle {
    anchors.left: parent.left
    width: 1
    height: parent.height
    opacity: prompt.statusOpacity
    color: prompt.failedInline ? prompt.urgentColor : prompt.accentColor
  }
  Rectangle {
    anchors.right: parent.right
    width: 1
    height: parent.height
    opacity: prompt.statusOpacity
    color: prompt.failedInline ? prompt.urgentColor : DesignTokens.strandEnd
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
      opacity: prompt.statusOpacity
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
          // The glyph shown before the field, "" for none.
          readonly property string glyph: slot.editable ? (slot.field.glyph || "") : ""

          width: content.width
          visible: !slot.field.hidden
          height: slot.editable ? Math.max(input.implicitHeight, connect.visible ? connect.implicitHeight : 0) : Math.max(fieldLabel.implicitHeight, readOnlyValue.implicitHeight)
          Component.onCompleted: {
            prompt.inputs[slot.index] = input
            prompt.noteText(slot.field.key || "", input.text)
            if (prompt.visible)
              Qt.callLater(prompt.focusFirst)
          }
          Component.onDestruction: {
            if (prompt.inputs[slot.index] === input)
              delete prompt.inputs[slot.index]
            prompt.pruneTexts()
          }

          Text {
            id: fieldGlyph
            objectName: slot.glyph !== "" ? (slot.field.key || "") + "Glyph" : ""
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(20)
            visible: slot.glyph !== ""
            textFormat: Text.PlainText
            text: slot.glyph
            horizontalAlignment: Text.AlignHCenter
            color: prompt.failedInline ? prompt.urgentColor : prompt.accentColor
            font.family: Style.font.family
            font.pixelSize: Style.font.iconLarge
          }
          TextField {
            id: input
            objectName: slot.editable ? (slot.field.key || "") + "Field" : ""
            anchors.left: fieldGlyph.visible ? fieldGlyph.right : parent.left
            anchors.leftMargin: fieldGlyph.visible ? Style.space(8) : 0
            // Every field leaves room for the connect button (hidden on all
            // but the last), so the fields line up; none without it.
            anchors.right: prompt.connectShown ? connect.left : parent.right
            anchors.rightMargin: prompt.connectShown ? Style.space(6) : 0
            anchors.verticalCenter: parent.verticalCenter
            visible: slot.editable
            readOnly: prompt.locked
            password: !!slot.field.secret
            placeholderText: prompt.failedInline ? prompt.failedText : (slot.field.placeholder || "")
            placeholderTextColor: prompt.failedInline ? prompt.urgentColor : Qt.darker(prompt.foregroundColor, 1.6)
            foreground: prompt.foregroundColor
            accent: prompt.accentColor
            horizontalPadding: Style.spacing.controlGap
            verticalPadding: Style.spacing.controlPaddingY
            onAccepted: prompt.advance(slot.index)
            onTextChanged: {
              prompt.noteText(slot.field.key || "", text)
              if (prompt.visible && slot.editable && text !== (slot.field.value || ""))
                prompt.edited(slot.field.key || "", text)
            }
            Keys.onEscapePressed: prompt.cancel()
            // A host's echoed value drives the text; a field without one
            // (Polkit) is never rewritten when `fields` is rebuilt.
            Binding on text {
              when: slot.field.value !== undefined
              value: slot.field.value || ""
              restoreMode: Binding.RestoreNone
            }
            Keys.onPressed: function (event) {
              if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Escape)
                prompt.unhandledKey(event)
            }
          }
          PanelActionButton {
            id: connect
            objectName: slot.last ? "connectButton" : ""
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: slot.last && prompt.connectShown
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
  // Breathing while busy inline; static at 0.7 when motion is disabled.
  SequentialAnimation {
    objectName: "promptPulse"
    loops: Animation.Infinite
    running: prompt.inlineStatus && prompt.busy && !prompt.failed && DesignTokens.motionEnabled
    onRunningChanged: if (!running)
      prompt.pulseOpacity = 1
    NumberAnimation {
      target: prompt
      property: "pulseOpacity"
      to: 0.45
      duration: 1200
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: prompt
      property: "pulseOpacity"
      to: 1
      duration: 1200
      easing.type: Easing.InOutSine
    }
  }
  HoverHandler {
    id: hover
    onPointChanged: if (prompt.pointerGate && hover.hovered && prompt.pointerGate.moved(prompt, {
      x: hover.point.position.x,
      y: hover.point.position.y
    }))
      prompt.pointerMovedAt = Date.now()
  }
}
