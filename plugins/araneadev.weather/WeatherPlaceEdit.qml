// The Aranea Weather dropdown's place edit: stock's search field (qs.Ui
// TextField) with a clear button beside it. Shown in the place label's
// stead while editing; opening it seeds the field from editText, selects
// it and focuses it. Typing (never seeding) reports the text; Enter
// commits and Esc cancels. Up and Down are taken before the field's own
// handling (which would move the text cursor) and reported as a step, so
// the host panel moves the highlighted suggestion as stock does. While a
// place saves, the field is disabled. Pure view: plain inputs in, signals
// out.
import QtQuick
import qs.Commons
import qs.Ui

Row {
  id: edit

  // Whether the editor is open.
  property bool active: false
  // The field's text when editing starts (or the host resets it while the
  // field is closed or not focused).
  property string editText: ""
  // Whether a committed place is being saved: the field is disabled.
  property bool saving: false
  // Whether the keyboard cursor is on the clear button.
  property bool clearCursor: false
  // The dropdown's PointerMoveGate, carrying layoutChangedAt.
  property var pointerGate: null
  // The field, for the dropdown and tests.
  readonly property alias field: placeField

  // Emitted when typing changes the field's text to TEXT.
  signal query(string text)
  // Emitted on Enter with the field's text.
  signal commit(string text)
  // Emitted on Esc.
  signal cancel
  // Emitted on Up (-1) or Down (+1): move the highlighted suggestion.
  signal step(int delta)
  // Emitted on a settled click on the clear button.
  signal clear
  // Emitted when the pointer really moves onto the clear button.
  signal clearHovered

  // Seeds the field from editText and focuses it with its text selected.
  function startEditing() {
    if (!edit.active)
      return
    placeField.text = edit.editText
    placeField.selectAll()
    placeField.forceActiveFocus()
  }

  // Stock's location keys: Esc cancels, Enter commits, Up and Down step
  // the highlighted suggestion (stock's handler lived on the field too).
  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      edit.cancel()
      event.accepted = true
    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
      edit.step(event.key === Qt.Key_Up ? -1 : 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      edit.commit(placeField.text)
      event.accepted = true
    }
  }

  spacing: Style.space(6)
  onActiveChanged: if (edit.active)
    Qt.callLater(edit.startEditing)
  // A host echo reaches the field only while the user is not typing in it
  // (closed, or not focused), so a stale echo never drops keystrokes.
  onEditTextChanged: if (placeField.text !== edit.editText && (!edit.active || !placeField.activeFocus))
    placeField.text = edit.editText
  Component.onCompleted: if (edit.active)
    Qt.callLater(edit.startEditing)

  TextField {
    id: placeField
    objectName: "placeField"
    width: Style.space(190)
    anchors.verticalCenter: parent.verticalCenter
    enabled: !edit.saving
    placeholderText: "Search city"
    font.pixelSize: Style.font.caption
    onTextEdited: edit.query(placeField.text)
    Keys.onPressed: function (event) {
      edit.handleKey(event)
    }
  }
  WeatherLink {
    objectName: "clearPlace"
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(18)
    horizontalAlignment: Text.AlignHCenter
    text: "✕"
    pixelSize: Style.font.body
    tooltipText: "Automatic location"
    hasCursor: edit.clearCursor
    pointerGate: edit.pointerGate
    onClicked: if (!edit.saving)
      edit.clear()
    onHoveredMoved: edit.clearHovered()
  }
}
