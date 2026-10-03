// The Aranea Tray manage panel's view: the "Tray icons" title and its
// caption, then one row per tray item (its icon, its name and two Filament
// pills: Pin, which reads "Pinned" and lights in the accent when pinned, and
// Hide, which reads "Hidden" and lights violet when hidden; a hidden item's
// icon and name are muted), "No tray items reporting." with no items, and
// the key hint. Drawn from one plain view object (Tray.qml's manage view)
// and reporting every user action through a single action signal. No
// settings, tray items or windows here: tests drive it with fixtures.
//
// The keyboard cursor outline shows on the {row, pill} cursor's pill only
// while view.cursor.active, never on hover; hover goes through a
// PointerMoveGate only. Rows are keyed by the tray item id and never
// rebuilt for a cursor or state change (the Repeater's model is the row
// count). The rows' keys changing (an equal list does not) and the panel
// emptying or filling stamp layoutChangedAt; a click within 300 ms of
// that, or of its row being built, is refused unless the pointer has
// really moved onto it since, and a click whose row key changed between
// press and release is refused. A pending row's pills breathe until the
// host's settings round-trip lands.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

Column {
  id: manage

  // View state built by Tray.qml: {rows: [{key (the tray item id), name
  // (its display name), icon (its image source), pinned, hidden, pending
  // (a pin or hide is still being saved)}], empty, cursor: {active, row,
  // pill (0 Pin, 1 Hide)}, keyHint}.
  property var view: ({})
  // When the layout last shifted under the pointer (Date.now()), 0 for
  // never; see noteLayoutChange.
  property real layoutChangedAt: 0
  // Filters synthetic hover from rows moving under a still pointer, and
  // carries layoutChangedAt to the controls that settle clicks.
  readonly property alias pointerGate: gate
  // The view's rows, or [].
  readonly property var rows: view && Array.isArray(view.rows) ? view.rows : []
  // Whether there are no tray items to manage.
  readonly property bool empty: !!(view && view.empty)
  // The view's cursor, or a neutral one.
  readonly property var cursor: view && view.cursor ? view.cursor : ({
      active: false,
      row: -1,
      pill: 0
    })
  // The rows' keys joined, so an equal list rebuilt by the host does not
  // stamp the layout.
  readonly property string rowKeys: rows.map(function (r) {
    return r && typeof r.key === "string" ? r.key : ""
  }).join("\n")

  // Emitted for every user action, NAME with its ARG:
  //   pin ({index, key}): row INDEX's Pin pill was clicked, KEY as the row
  //     held it when pressed (never when the row's key changed
  //     underneath);
  //   hide ({index, key}): the same for its Hide pill;
  //   hover ({row}): the pointer really moved onto row ROW (through the
  //     gate).
  signal action(string name, var arg)

  // Stamps layoutChangedAt: something moved the rows without rebuilding
  // them.
  function noteLayoutChange() {
    manage.layoutChangedAt = Date.now()
  }

  // Resets the pointer gate; called after every keyboard-driven change so
  // a stale pointer sample never counts as a real move.
  function disarmPointer() {
    gate.reset()
  }

  // The key of row INDEX, or "".
  function keyAt(index) {
    var row = manage.rows[index]
    return row && typeof row.key === "string" ? row.key : ""
  }

  // Reports NAME ("pin" or "hide") for row INDEX if it still holds KEY;
  // refused otherwise.
  function toggleAt(name, index, key) {
    if (!key || manage.keyAt(index) !== key)
      return
    manage.action(name, {
      index: index,
      key: key
    })
  }

  // Whether the keyboard cursor is on PILL (0 Pin, 1 Hide) of row INDEX.
  function cursorOn(index, pill) {
    return !!manage.cursor.active && manage.cursor.row === index && manage.cursor.pill === pill
  }

  // Symbolic icons are tinted to the foreground, as stock's tray icons
  // are: true when ICON's name ends in "-symbolic".
  function iconIsSymbolic(icon) {
    var name = String(icon || "").split("?")[0]
    return name.slice(-9) === "-symbolic"
  }

  // About the mockup's card width; a host may set its own.
  width: Style.space(320)
  spacing: Style.space(8)
  onRowKeysChanged: manage.noteLayoutChange()
  onEmptyChanged: manage.noteLayoutChange()

  Text {
    objectName: "manageTitle"
    width: parent.width
    text: "Tray icons"
    elide: Text.ElideRight
    color: Aranea.DesignTokens.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.title
    font.bold: true
  }
  Text {
    objectName: "manageCaption"
    width: parent.width
    text: "Pinned icons stay visible. Hidden icons never show."
    wrapMode: Text.WordWrap
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  Rectangle {
    // The hairline over the rows.
    width: parent.width
    height: Math.max(1, Style.spacing.hairline)
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
  }
  Column {
    id: rowColumn
    width: parent.width
    visible: manage.rows.length > 0
    spacing: Style.space(2)

    Repeater {
      model: manage.rows.length
      Item {
        id: row
        required property int index
        // This row's item, read live so the row is never rebuilt.
        readonly property var entry: manage.rows[row.index] || ({})
        // The row's key (the tray item id).
        readonly property string key: manage.keyAt(row.index)
        // Whether the item is hidden (its icon and name are muted).
        readonly property bool hidden: !!row.entry.hidden
        // When the row was built (Date.now()).
        property real createdAt: 0
        // When the gate last accepted a real pointer move onto the row or
        // one of its pills.
        property real pointerMovedAt: 0
        // The key under the last press on a pill, compared on release.
        property string pressedKey: ""

        // Whether a pointer click may act on this row's pills (their
        // clickGate): settled since it was built and since the panel's
        // last layout shift, or moved onto since.
        function clickSettled() {
          return ClickSettle.clickSettled({
            now: Date.now(),
            createdAt: row.createdAt,
            movedAt: row.pointerMovedAt,
            layoutChangedAt: manage.layoutChangedAt
          })
        }

        // Reports a real pointer move onto the row.
        function noteMove() {
          row.pointerMovedAt = Date.now()
          manage.action("hover", {
            row: row.index
          })
        }

        // Reports NAME for this row if the press held the key it still
        // holds, then forgets the press.
        function release(name) {
          var key = row.pressedKey
          row.pressedKey = ""
          if (key !== "" && key === row.key)
            manage.toggleAt(name, row.index, key)
        }

        objectName: "manageRow"
        width: rowColumn.width
        height: Style.space(30)
        Component.onCompleted: row.createdAt = Date.now()

        MouseArea {
          id: rowMouse
          // Hover only: the pills take the clicks.
          anchors.fill: parent
          acceptedButtons: Qt.NoButton
          hoverEnabled: true
          onPositionChanged: function (mouse) {
            if (gate.moved(rowMouse, mouse))
              row.noteMove()
          }
        }
        Item {
          id: iconSlot
          width: Style.space(16)
          height: Style.space(16)
          x: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          opacity: row.hidden ? 0.4 : 1
          // Whether the icon is tinted to the foreground.
          readonly property bool symbolic: manage.iconIsSymbolic(row.entry.icon)

          Image {
            id: iconImage
            objectName: "rowIcon"
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            // Decode at physical pixels, as stock's tray icons do.
            sourceSize.width: Math.round(width * Screen.devicePixelRatio)
            sourceSize.height: Math.round(height * Screen.devicePixelRatio)
            source: String(row.entry.icon || "")
            // Kept as a hidden layer so the effect can sample it.
            visible: !iconSlot.symbolic
            layer.enabled: iconSlot.symbolic
          }
          MultiEffect {
            anchors.fill: iconImage
            source: iconImage
            visible: iconSlot.symbolic
            colorization: 1.0
            colorizationColor: Aranea.DesignTokens.foreground
          }
        }
        Text {
          objectName: "rowName"
          anchors.left: iconSlot.right
          anchors.leftMargin: Style.space(10)
          anchors.right: pills.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: String(row.entry.name || "")
          elide: Text.ElideRight
          color: row.hidden ? Util.alpha(Aranea.DesignTokens.foreground, 0.55) : Aranea.DesignTokens.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Row {
          id: pills
          anchors.right: parent.right
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          Aranea.FilamentPill {
            objectName: "pinPill"
            text: row.entry.pinned ? "Pinned" : "Pin"
            selected: !!row.entry.pinned
            busy: !!row.entry.pending
            hasCursor: manage.cursorOn(row.index, 0)
            pointerGate: manage.pointerGate
            clickGate: row
            onPressed: row.pressedKey = row.key
            onClicked: row.release("pin")
            onHoveredMoved: row.noteMove()
          }
          Aranea.FilamentPill {
            objectName: "hidePill"
            text: row.hidden ? "Hidden" : "Hide"
            selected: row.hidden
            selectedColor: Aranea.DesignTokens.strandEnd
            busy: !!row.entry.pending
            hasCursor: manage.cursorOn(row.index, 1)
            pointerGate: manage.pointerGate
            clickGate: row
            onPressed: row.pressedKey = row.key
            onClicked: row.release("hide")
            onHoveredMoved: row.noteMove()
          }
        }
      }
    }
  }
  Text {
    objectName: "emptyText"
    visible: manage.empty
    width: parent.width
    text: "No tray items reporting."
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
  Text {
    objectName: "keyHint"
    width: parent.width
    topPadding: Style.space(4)
    text: manage.view && manage.view.keyHint ? manage.view.keyHint : ""
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.3)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  PointerMoveGate {
    id: gate
    // The panel's last layout shift, for the controls' clickSettled().
    property real layoutChangedAt: manage.layoutChangedAt

    referenceItem: manage
  }
}
