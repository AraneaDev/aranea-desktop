// The notification center's Filament header and footer: the shared
// DropdownHeader (title "Notifications" plus the view's caption, "N
// unread", "Nothing new" or the quiet-hours text), a "Do not disturb" row
// with a FilamentSwitch, the empty state ("All caught up") when the inbox
// is empty, a default slot where Panel.qml places the row list
// between the header and the footer, a "Clear all" FilamentPill (two-step
// confirm) and the key hint line. One plain view object in (see `view`),
// every user action reported through a single action signal. No service
// or inbox here: tests drive it with fixtures.
//
// The keyboard cursor outline (dndCursor, clearCursor) shows only while a
// host says so, never on hover. Hover is not wired here: neither control
// changes with it. A click on the DND switch or the Clear pill is
// refused within 300 ms of this view's own layout shifting (its caption
// changing height, the Clear row showing or hiding) or of the slot's
// content doing so, when the host calls noteLayoutChange() for it, the
// same pattern WeatherDropdown uses for its sections.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

ColumnLayout {
  id: root

  // View state built by the host: {count, caption ("N unread", "Nothing
  // new" or the quiet-hours text), glyph (the header's bell; the plain
  // bell when missing), dnd: {on, busy}, clear: {visible,
  // confirming, label ("Clear all" or "Confirm clear (N)")}, keyHint}.
  property var view: ({})
  // Whether the keyboard cursor is on the "Do not disturb" row; kept out
  // of view, as WeatherDropdown keeps editText out of its view.
  property bool dndCursor: false
  // Whether the keyboard cursor is on the "Clear all" pill.
  property bool clearCursor: false
  // When this view's layout last shifted (Date.now()), 0 for never; see
  // noteLayoutChange.
  property real layoutChangedAt: 0
  // Filters synthetic hover from controls moving under a still pointer,
  // and carries layoutChangedAt to the Clear pill, the same gate
  // WeatherDropdown exposes for its sections. Unused by the DND switch,
  // which settles through clickSettled() instead (FilamentSwitch has no
  // pointerGate fallback of its own).
  readonly property alias pointerGate: gate
  // Default slot: the host's row list sits here, between the header and
  // the footer.
  default property alias content: slot.data
  // Where the slot starts (the header, DND row and empty state above it),
  // so the host can size its list and stamp its layout without reading
  // this view's own height, which includes the list.
  readonly property real slotTop: slot.y
  // The height below the slot: the Clear row while it shows and the key
  // hint line, each with the column spacing.
  readonly property real footerHeight: (clearRow.visible ? clearRow.implicitHeight + root.spacing : 0) + keyHint.implicitHeight + root.spacing

  // The view's dnd part, or an off, idle one.
  readonly property var dnd: root.view && root.view.dnd ? root.view.dnd : ({
      on: false,
      busy: false
    })
  // The view's clear part, or a hidden one.
  readonly property var clear: root.view && root.view.clear ? root.view.clear : ({
      visible: false,
      confirming: false,
      label: "Clear all"
    })
  // The view's count, or 0.
  readonly property int count: root.view && typeof root.view.count === "number" ? root.view.count : 0

  // Emitted for every user action, NAME with its ARG: toggleDnd ({}), the
  // DND switch was clicked or activated; clearAll ({}), the Clear-all
  // pill was clicked or activated.
  signal action(string name, var arg)

  // Stamps layoutChangedAt: something moved the DND switch or the Clear
  // pill without rebuilding them (the host's slot content changing
  // height counts too; the host calls this directly for it).
  function noteLayoutChange() {
    root.layoutChangedAt = Date.now()
  }

  // Resets the pointer gate; the host calls it after every keyboard-driven
  // change, as NotificationList's disarmPointer, so a stale pointer sample
  // never counts as a real move.
  function disarmPointer() {
    gate.reset()
  }

  // Whether a pointer click on the DND switch may act: settled since this
  // view's last layout shift. Passed as the switch's clickGate, the same
  // "anything with clickSettled()" contract NodeDeviceRow and
  // DisplaysControlRow satisfy.
  function clickSettled() {
    return ClickSettle.clickSettled({
      now: Date.now(),
      layoutChangedAt: root.layoutChangedAt
    })
  }

  spacing: Style.space(10)

  Aranea.DropdownHeader {
    id: header
    refined: true
    objectName: "centerHeader"
    Layout.fillWidth: true
    glyph: root.view && root.view.glyph ? String(root.view.glyph) : String.fromCodePoint(0xf009a)
    title: "Notifications"
    caption: root.view && root.view.caption ? String(root.view.caption) : ""
    onHeightChanged: root.noteLayoutChange()
  }
  RowLayout {
    id: dndRow
    objectName: "dndRow"
    Layout.fillWidth: true
    Text {
      objectName: "dndLabel"
      Layout.fillWidth: true
      text: "Do not disturb"
      color: Aranea.DesignTokens.foreground
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.body
    }
    Aranea.FilamentSwitch {
      id: dndSwitch
      objectName: "dndSwitch"
      checked: !!root.dnd.on
      busy: !!root.dnd.busy
      hasCursor: root.dndCursor
      clickGate: root
      onToggled: root.action("toggleDnd", ({}))
    }
  }
  Aranea.EmptyState {
    objectName: "emptyState"
    visible: root.count === 0
    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight
    imageSource: Aranea.RuntimePaths.glyphUrl
    imageSize: Style.space(28)
    imageOpacity: 0.6
    message: "All caught up"
    messageSize: Style.font.body
    spacing: Style.space(6)
    fontFamily: Aranea.Typography.uiFamily
    foreground: Aranea.DesignTokens.foreground
  }
  Item {
    id: slot
    objectName: "centerSlot"
    Layout.fillWidth: true
    Layout.preferredHeight: slot.childrenRect.height
  }
  RowLayout {
    id: clearRow
    objectName: "clearRow"
    Layout.fillWidth: true
    visible: !!root.clear.visible
    onVisibleChanged: root.noteLayoutChange()
    Item {
      Layout.fillWidth: true
    }
    Aranea.FilamentPill {
      id: clearPill
      refined: true
      objectName: "clearPill"
      text: String(root.clear.label)
      hasCursor: root.clearCursor
      pointerGate: root.pointerGate
      onClicked: root.action("clearAll", ({}))
    }
  }
  Text {
    id: keyHint
    objectName: "keyHint"
    Layout.fillWidth: true
    text: root.view && root.view.keyHint ? String(root.view.keyHint) : ""
    color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  PointerMoveGate {
    id: gate
    // This view's last layout shift, for the Clear pill's clickSettled().
    property real layoutChangedAt: root.layoutChangedAt

    referenceItem: root
  }
}
