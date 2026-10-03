// Grouped notification list presentation; action policy remains in Panel.qml.
//
// Rows are keyed by entry or group (InboxLogic.rowKey) and never rebuilt
// for a cursor change: the ListView's model is the row count and each row
// reads its data live, so an equal-length update (a re-sort, a collapse)
// keeps the same row items. The keyboard cursor draws the mint outline
// only while cursor.active; hover draws nothing and goes through a
// PointerMoveGate only. Every click is keyed: a press records the row's
// key, and the release is refused when the key under it has changed, or
// within 300 ms of the layout shifting (the rows' keys, a group collapsing
// or expanding, a "+N more" count, the header height, a scroll) unless the
// pointer has really moved onto the row since (ClickSettle).
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons
import qs.Ui
import "components"
import "InboxLogic.js" as InboxLogic
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

Item {
  id: root
  // Center rows (InboxLogic.centerRows): group, entry and "more" rows.
  property var rows: []
  // The keyboard cursor: active (the outline shows only while true) and
  // index (a position in rows).
  property var cursor: ({
      active: false,
      index: -1
    })
  // Clock for the relative time labels (Date.now()).
  property real now: Date.now()
  // The notification service, for motion and corner radius; null in tests.
  property var service: null
  // The bar, for its font family; null in tests.
  property var bar: null
  // Card corner radius when there is no service.
  property real cornerRadius: 0
  // Font family for the group rows and "+N more" rows.
  property string fontFamily: bar && bar.fontFamily ? bar.fontFamily : Style.font.family
  // Whether cards animate swipes when there is no service.
  property bool motionEnabled: true
  // The height of the header above the list; a change moves the rows under
  // the pointer and stamps the layout.
  property real headerHeight: 0
  // When the layout last shifted under the pointer (Date.now()), 0 for
  // never; see noteLayoutChange.
  property real layoutChangedAt: 0
  // Filters synthetic hover from rows moving under a still pointer, and
  // carries layoutChangedAt to the rows' clickSettled().
  readonly property alias pointerGate: gate
  // The list's content height, for the host's sizing.
  readonly property real contentHeight: list.contentHeight
  // The row the keyboard cursor is on while active, or -1.
  readonly property int cursorIndex: cursor && cursor.active && typeof cursor.index === "number" ? cursor.index : -1
  // The rows' keys joined, so an equal list rebuilt by the host does not
  // stamp the layout.
  readonly property string rowKeys: root.rows.map(function (r) {
    return InboxLogic.rowKey(r)
  }).join("\n")
  // Each group's collapsed flag, joined: a collapse that keeps the keys
  // still stamps the layout.
  readonly property string collapseState: root.rows.map(function (r) {
    return r && r.kind === "group" ? (r.collapsed ? "1" : "0") : ""
  }).join(",")
  // Each "+N more" row's hidden count, joined.
  readonly property string moreState: root.rows.map(function (r) {
    return r && r.kind === "more" ? String(r.hidden) : ""
  }).join(",")

  // Emitted for every user action, NAME with its ARG:
  //   open ({index, key}): an entry card or a "+N more" row was clicked;
  //   dismiss ({index, key}): an entry's close was clicked or it was swiped
  //     away;
  //   toggle ({index, key}): a group header was clicked (collapse/expand);
  //   clearGroup ({index, key}): a group's close was clicked;
  //   hover ({index, key}): the pointer really moved onto an entry or
  //     "+N more" row (through the gate).
  // INDEX is a position in rows and KEY the row's key when pressed; an
  // action is never emitted when the row's key has changed underneath.
  signal action(string name, var arg)

  // Stamps layoutChangedAt: something moved the rows without rebuilding
  // them.
  function noteLayoutChange(): void {
    root.layoutChangedAt = Date.now()
  }

  // Resets the pointer gate; called after every keyboard-driven change so
  // a stale pointer sample never counts as a real move.
  function disarmPointer(): void {
    gate.reset()
  }

  // The key of row INDEX (InboxLogic.rowKey), or "".
  function keyAt(index: int): string {
    return InboxLogic.rowKey(root.rows[index] || null)
  }

  // Emits action NAME for row INDEX if it still holds KEY and NAME fits
  // its kind (open: entry or more; dismiss: entry; toggle and clearGroup:
  // group); refused otherwise.
  function actOn(name: string, index: int, key: string): void {
    var row = root.rows[index]
    if (!key || !row || root.keyAt(index) !== key)
      return
    var fits = name === "open" ? (row.kind === "entry" || row.kind === "more") : name === "dismiss" ? row.kind === "entry" : (name === "toggle" || name === "clearGroup") ? row.kind === "group" : false
    if (fits)
      root.action(name, {
        index: index,
        key: key
      })
  }

  // The row item (card, group row or "+N more" row) at INDEX, or null when
  // it is not built.
  function itemAtIndex(index: int): var {
    var loader = list.itemAtIndex(index)
    return loader ? loader.item : null
  }

  // Keeps Panel.qml's cursor navigation independent of the ListView instance.
  function positionViewAtIndex(index: int, mode: int): void {
    list.positionViewAtIndex(index, mode)
  }

  implicitHeight: list.contentHeight
  onRowKeysChanged: root.noteLayoutChange()
  onCollapseStateChanged: root.noteLayoutChange()
  onMoreStateChanged: root.noteLayoutChange()
  onHeaderHeightChanged: root.noteLayoutChange()

  ListView {
    id: list
    anchors.fill: parent
    model: root.rows.length
    spacing: Style.space(6)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    // A scroll moves the rows under a still pointer.
    onContentYChanged: root.noteLayoutChange()

    delegate: Loader {
      id: rowLoader
      required property int index
      // This row, read live so the row is never rebuilt for a change of
      // content.
      readonly property var row: root.rows[rowLoader.index] || ({})
      // This row's entry, or an empty one.
      readonly property var entry: rowLoader.row.entry || ({})
      // The row's key.
      readonly property string key: root.keyAt(rowLoader.index)
      // Whether the keyboard cursor outline shows here.
      readonly property bool hasCursor: root.cursorIndex === rowLoader.index
      width: list.width
      sourceComponent: rowLoader.row.kind === "group" ? groupRow : (rowLoader.row.kind === "more" ? moreRow : entryRow)

      Component {
        id: groupRow
        NotificationGroupRow {
          objectName: "groupRow"
          app: String(rowLoader.row.app || "")
          count: Number(rowLoader.row.count) || 0
          collapsed: !!rowLoader.row.collapsed
          fontFamily: root.fontFamily
          pointerGate: gate
          rowKey: rowLoader.key
          onGroupClicked: if (clickSettled() && pressedKey === rowLoader.key)
            root.actOn("toggle", rowLoader.index, pressedKey)
          onCloseRequested: if (clickSettled() && pressedKey === rowLoader.key)
            root.actOn("clearGroup", rowLoader.index, pressedKey)
        }
      }

      Component {
        id: moreRow
        Item {
          id: more
          objectName: "moreRow"
          // When the row was built (Date.now()).
          property real createdAt: 0
          // When the gate last accepted a real pointer move onto the row.
          property real pointerMovedAt: 0
          // The key under the last press, compared on release.
          property string pressedKey: ""
          // The row's key, as the hover and click checks read it.
          readonly property string rowKey: rowLoader.key

          // Whether a pointer click may act on this row (ClickSettle).
          function clickSettled(): bool {
            return ClickSettle.clickSettled({
              now: Date.now(),
              createdAt: more.createdAt,
              movedAt: more.pointerMovedAt,
              layoutChangedAt: root.layoutChangedAt
            })
          }

          implicitWidth: moreText.implicitWidth
          implicitHeight: moreText.implicitHeight
          Component.onCompleted: more.createdAt = Date.now()

          Rectangle {
            // The keyboard cursor outline (mint, keyboard only).
            objectName: "cursorOutline"
            anchors.fill: parent
            color: "transparent"
            border.width: rowLoader.hasCursor ? 1 : 0
            border.color: Aranea.DesignTokens.accent
            visible: rowLoader.hasCursor
          }
          Text {
            id: moreText
            objectName: "moreText"
            leftPadding: Style.space(12)
            topPadding: Style.space(2)
            bottomPadding: Style.space(2)
            text: "+" + (Number(rowLoader.row.hidden) || 0) + " more"
            color: Qt.darker(Color.popups.text, 1.3)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          MouseArea {
            id: moreArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: more.pressedKey = rowLoader.key
            onPositionChanged: function (mouse) {
              if (gate.moved(moreArea, mouse)) {
                more.pointerMovedAt = Date.now()
                root.action("hover", {
                  index: rowLoader.index,
                  key: rowLoader.key
                })
              }
            }
            onClicked: {
              var key = more.pressedKey
              more.pressedKey = ""
              if (more.clickSettled() && key !== "" && key === rowLoader.key)
                root.actOn("open", rowLoader.index, key)
            }
          }
        }
      }

      Component {
        id: entryRow
        NotificationCard {
          objectName: "entryCard"
          width: list.width
          compact: true
          hasCursor: rowLoader.hasCursor
          pointerGate: gate
          rowKey: rowLoader.key
          motionEnabled: root.service ? root.service.motionEnabled : root.motionEnabled
          app: String(rowLoader.entry.app || "")
          appIcon: String(rowLoader.entry.appIcon || "")
          summary: String(rowLoader.entry.summary || "")
          body: String(rowLoader.entry.body || "")
          image: String(rowLoader.entry.image || "")
          glyph: String(rowLoader.entry.glyph || "")
          urgency: typeof rowLoader.entry.urgency === "number" ? rowLoader.entry.urgency : 1
          timeLabel: InboxLogic.relativeTime(rowLoader.entry.timestamp, root.now)
          cornerRadius: root.service ? root.service.cornerRadius : root.cornerRadius
          fontFamily: root.bar ? root.bar.fontFamily : root.fontFamily
          onPointerMoved: root.action("hover", {
            index: rowLoader.index,
            key: rowLoader.key
          })
          onCardClicked: if (clickSettled() && pressedKey === rowLoader.key)
            root.actOn("open", rowLoader.index, pressedKey)
          onCloseRequested: if (clickSettled() && pressedKey === rowLoader.key)
            root.actOn("dismiss", rowLoader.index, pressedKey)
          // A swipe is a deliberate gesture, not settled, but still keyed.
          onSwipeDismissed: if (pressedKey === rowLoader.key)
            root.actOn("dismiss", rowLoader.index, pressedKey)
        }
      }
    }
  }

  PointerMoveGate {
    id: gate
    // The list's last layout shift, for the rows' clickSettled().
    property real layoutChangedAt: root.layoutChangedAt

    referenceItem: root
  }
}
