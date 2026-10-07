// The Aranea Tray app menu's view: the app title at the root, or the
// breadcrumb (a back glyph and the crumb) inside a submenu, then one row
// per menu entry (a check or radio mark when lit, the entry's icon, its
// label and a child glyph for a submenu; disabled rows dimmed, separators
// as hairlines), "No menu entries" when the menu is empty, and the key
// hint. Drawn from one plain view object (Tray.qml's menu view) and
// reporting every user action through a single action signal. No DBus menu,
// settings or windows here: tests drive it with fixtures.
//
// The keyboard cursor outline shows only while view.cursor.active, never on
// hover; hover goes through a PointerMoveGate only, and only onto rows that
// can be activated, where it draws the row's fill. A lit check or radio
// entry carries the selected highlight. Rows are keyed by the DBus entry id plus label and are
// never rebuilt for a cursor change (the Repeater's model is the row
// count). The rows' keys changing (an equal list does not), the depth
// changing, the menu emptying or filling and the list scrolling stamp
// layoutChangedAt; a click within 300 ms of that, or of its row being
// built, is refused unless the pointer has really moved onto it since, and
// a click whose row key changed between press and release is refused.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

Column {
  id: menu

  // View state built by Tray.qml: {title (the app's), crumb (the app and
  // submenu titles joined with a right angle quote, shown below the root),
  // depth (0 at the root), rows: [{key (entry id and label), label,
  // separator, enabled, selectable, mark ("", "check" or "radio"), markOn,
  // hasChildren, icon, index (the entry's source index)}] (TrayLogic's
  // menuRows), empty, cursor: {active, index (a position in rows)},
  // keyHint}.
  property var view: ({})
  // The tallest the row list grows before it scrolls, in px.
  property real maxListHeight: Style.space(420)
  // When the layout last shifted under the pointer (Date.now()), 0 for
  // never; see noteLayoutChange.
  property real layoutChangedAt: 0
  // Filters synthetic hover from rows moving under a still pointer, and
  // carries layoutChangedAt to the controls that settle clicks.
  readonly property alias pointerGate: gate
  // The view's rows, or [].
  readonly property var rows: view && Array.isArray(view.rows) ? view.rows : []
  // The menu level: 0 at the root, one more per submenu drilled into.
  readonly property int depth: view && typeof view.depth === "number" && view.depth > 0 ? view.depth : 0
  // Whether the menu has no entries to show.
  readonly property bool empty: !!(view && view.empty)
  // The view's cursor, or a neutral one.
  readonly property var cursor: view && view.cursor ? view.cursor : ({
      active: false,
      index: -1
    })
  // The row the keyboard cursor is on while active, or -1.
  readonly property int cursorIndex: cursor.active && typeof cursor.index === "number" ? cursor.index : -1
  // The rows' keys joined, so an equal list rebuilt by the host does not
  // stamp the layout.
  readonly property string rowKeys: rows.map(function (r) {
    return r && typeof r.key === "string" ? r.key : ""
  }).join("\n")

  // Emitted for every user action, NAME with its ARG:
  //   activate ({index, key}): row INDEX (a position in rows) was clicked,
  //     KEY as the row held it when pressed (never a separator or a
  //     disabled row, never when the row's key changed underneath);
  //   back ({}): the breadcrumb was clicked (below the root only);
  //   hover ({index}): the pointer really moved onto row INDEX (through
  //     the gate).
  signal action(string name, var arg)

  // Stamps layoutChangedAt: something moved the rows without rebuilding
  // them.
  function noteLayoutChange() {
    menu.layoutChangedAt = Date.now()
  }

  // Resets the pointer gate; called after every keyboard-driven change so
  // a stale pointer sample never counts as a real move.
  function disarmPointer() {
    gate.reset()
  }

  // The key of row INDEX, or "".
  function keyAt(index) {
    var row = menu.rows[index]
    return row && typeof row.key === "string" ? row.key : ""
  }

  // Whether row INDEX can be activated: not a separator, enabled and
  // selectable.
  function selectableAt(index) {
    var row = menu.rows[index]
    return !!row && !row.separator && row.enabled !== false && row.selectable !== false
  }

  // Activates row INDEX if it still holds KEY and can be activated;
  // refused otherwise.
  function activateAt(index, key) {
    if (!key || menu.keyAt(index) !== key || !menu.selectableAt(index))
      return
    menu.action("activate", {
      index: index,
      key: key
    })
  }

  // Scrolls the row list back to the top (the host's resetTrayMenu, as
  // stock reset its Flickable before a menu reopens).
  function resetScroll() {
    list.contentY = 0
  }

  // Scrolls the row list so the keyboard cursor's row is in view.
  function revealCursor() {
    menu.revealRow(menu.cursorIndex)
  }

  // Scrolls the row list so row INDEX is fully in view.
  function revealRow(index) {
    var item = index >= 0 ? rowRepeater.itemAt(index) : null
    if (!item)
      return
    if (item.y < list.contentY)
      list.contentY = item.y
    else if (item.y + item.height > list.contentY + list.height)
      list.contentY = item.y + item.height - list.height
  }

  // About the mockup's card width; a host may set its own.
  width: Style.space(300)
  spacing: Style.space(6)
  onRowKeysChanged: menu.noteLayoutChange()
  onEmptyChanged: menu.noteLayoutChange()
  // A new level shows from its top, as stock's does.
  onDepthChanged: {
    list.contentY = 0
    menu.noteLayoutChange()
  }
  // Later, so a depth change in the same view assignment resets the scroll
  // first.
  onCursorIndexChanged: Qt.callLater(menu.revealCursor)

  Item {
    id: header
    width: parent.width
    implicitHeight: Style.space(22)

    // The root's header: the app title and "app menu".
    Text {
      objectName: "menuTitle"
      visible: menu.depth === 0
      anchors.left: parent.left
      anchors.right: rootCaption.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: String(menu.view && menu.view.title ? menu.view.title : "")
      elide: Text.ElideRight
      color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.4
    }
    Text {
      id: rootCaption
      objectName: "menuCaption"
      visible: menu.depth === 0
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "app menu"
      color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.caption
    }

    // The breadcrumb below the root: a back glyph and the crumb, the whole
    // row a settled click back.
    Item {
      id: crumbRow
      objectName: "crumbRow"
      // When the gate last accepted a real pointer move onto the crumb.
      property real pointerMovedAt: 0

      // Whether a pointer click may go back (ClickSettle over the menu's
      // last layout shift and the last real pointer move).
      function clickSettled() {
        return ClickSettle.clickSettled({
          now: Date.now(),
          movedAt: crumbRow.pointerMovedAt,
          layoutChangedAt: menu.layoutChangedAt
        })
      }

      visible: menu.depth > 0
      anchors.fill: parent

      Aranea.HoverTint {
        pointerGate: gate
      }
      Text {
        id: crumbBack
        objectName: "crumbBack"
        width: Style.space(14)
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        text: String.fromCodePoint(0x2039)
        color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
        font.family: Aranea.Typography.iconFamily
        font.pixelSize: Style.font.body
      }
      Text {
        objectName: "crumbText"
        anchors.left: crumbBack.right
        anchors.leftMargin: Style.space(8)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: String(menu.view && menu.view.crumb ? menu.view.crumb : "")
        elide: Text.ElideRight
        color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
        font.family: Aranea.Typography.uiFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.4
      }
      MouseArea {
        id: crumbMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: function (mouse) {
          if (gate.moved(crumbMouse, mouse))
            crumbRow.pointerMovedAt = Date.now()
        }
        onClicked: if (crumbRow.clickSettled())
          menu.action("back", {})
      }
    }
  }
  Rectangle {
    // The hairline under the header.
    width: parent.width
    height: Math.max(1, Style.spacing.hairline)
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
  }
  Flickable {
    id: list
    objectName: "menuList"
    width: parent.width
    height: Math.min(contentHeight, menu.maxListHeight)
    visible: menu.rows.length > 0
    contentWidth: width
    contentHeight: rowColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height
    // A scroll moves the rows under a still pointer.
    onContentYChanged: menu.noteLayoutChange()

    Column {
      id: rowColumn
      width: list.width
      spacing: 0

      Repeater {
        id: rowRepeater
        model: menu.rows.length
        Item {
          id: row
          required property int index
          // This row's entry, read live so the row is never rebuilt.
          readonly property var entry: menu.rows[row.index] || ({})
          // The row's key (entry id and label).
          readonly property string key: menu.keyAt(row.index)
          // Whether the row is a hairline separator.
          readonly property bool isSeparator: !!row.entry.separator
          // Whether the row can be activated (and hovered).
          readonly property bool selectable: menu.selectableAt(row.index)
          // Whether the keyboard cursor outline shows here.
          readonly property bool hasCursor: menu.cursorIndex === row.index
          // The lit mark: a check, a radio dot, or "".
          readonly property string markText: !row.entry.markOn ? "" : row.entry.mark === "radio" ? String.fromCodePoint(0x25CF) : row.entry.mark === "check" ? String.fromCodePoint(0x2713) : ""
          // When the row was built (Date.now()).
          property real createdAt: 0
          // When the gate last accepted a real pointer move onto the row.
          property real pointerMovedAt: 0
          // The key under the last press, compared on release.
          property string pressedKey: ""

          // Whether a pointer click may act on this row (ClickSettle).
          function clickSettled() {
            return ClickSettle.clickSettled({
              now: Date.now(),
              createdAt: row.createdAt,
              movedAt: row.pointerMovedAt,
              layoutChangedAt: menu.layoutChangedAt
            })
          }

          objectName: "menuRow"
          width: rowColumn.width
          height: row.isSeparator ? Style.space(9) : Style.space(26)
          opacity: !row.isSeparator && row.entry.enabled === false ? 0.45 : 1
          Component.onCompleted: row.createdAt = Date.now()

          Rectangle {
            // The selected highlight: a lit check or radio entry is a
            // current choice.
            objectName: "selectedFill"
            anchors.fill: parent
            color: Aranea.DesignTokens.selectedFill
            visible: !row.isSeparator && !!row.entry.markOn
          }
          Aranea.HoverTint {
            active: row.selectable
            pointerGate: gate
          }
          Rectangle {
            // The keyboard cursor outline.
            objectName: "cursorOutline"
            anchors.fill: parent
            color: row.hasCursor ? Util.alpha(Aranea.DesignTokens.accent, 0.08) : "transparent"
            border.width: row.hasCursor ? 1 : 0
            border.color: Aranea.DesignTokens.accent
          }
          Rectangle {
            objectName: "separatorLine"
            visible: row.isSeparator
            width: parent.width
            height: Math.max(1, Style.spacing.hairline)
            anchors.verticalCenter: parent.verticalCenter
            color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
          }
          Text {
            id: mark
            objectName: "rowMark"
            visible: !row.isSeparator
            width: Style.space(14)
            x: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: row.markText
            color: Aranea.DesignTokens.accent
            font.family: Aranea.Typography.iconFamily
            font.pixelSize: Style.font.body
          }
          Image {
            id: icon
            objectName: "rowIcon"
            visible: !row.isSeparator && String(row.entry.icon || "") !== ""
            width: Style.space(16)
            height: Style.space(16)
            anchors.left: mark.right
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            fillMode: Image.PreserveAspectFit
            // Decode at physical pixels, as stock's menu icons do.
            sourceSize.width: Math.round(width * Screen.devicePixelRatio)
            sourceSize.height: Math.round(height * Screen.devicePixelRatio)
            source: icon.visible ? String(row.entry.icon) : ""
          }
          Text {
            objectName: "rowLabel"
            visible: !row.isSeparator
            anchors.left: icon.visible ? icon.right : mark.right
            anchors.leftMargin: Style.space(8)
            anchors.right: childGlyph.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String(row.entry.label || "")
            elide: Text.ElideRight
            color: Aranea.DesignTokens.foreground
            font.family: Aranea.Typography.uiFamily
            font.pixelSize: Style.font.body
          }
          Text {
            id: childGlyph
            objectName: "childGlyph"
            visible: !row.isSeparator && !!row.entry.hasChildren
            anchors.right: parent.right
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0x203A)
            color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
            font.family: Aranea.Typography.iconFamily
            font.pixelSize: Style.font.body
          }
          MouseArea {
            id: rowMouse
            anchors.fill: parent
            enabled: row.selectable
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: row.pressedKey = row.key
            onPositionChanged: function (mouse) {
              if (gate.moved(rowMouse, mouse)) {
                row.pointerMovedAt = Date.now()
                menu.action("hover", {
                  index: row.index
                })
              }
            }
            onClicked: {
              var key = row.pressedKey
              row.pressedKey = ""
              if (row.clickSettled() && key !== "" && key === row.key)
                menu.activateAt(row.index, key)
            }
          }
        }
      }
    }
  }
  Text {
    objectName: "emptyText"
    visible: menu.empty
    width: parent.width
    topPadding: Style.space(4)
    bottomPadding: Style.space(4)
    text: "No menu entries"
    color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: Style.font.body
  }
  Text {
    objectName: "keyHint"
    width: parent.width
    topPadding: Style.space(4)
    text: menu.view && menu.view.keyHint ? menu.view.keyHint : ""
    color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  PointerMoveGate {
    id: gate
    // The menu's last layout shift, for the controls' clickSettled().
    property real layoutChangedAt: menu.layoutChangedAt

    referenceItem: menu
  }
}
