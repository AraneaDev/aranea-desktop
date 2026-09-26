// Notification bell + center. The bell shows the inbox count; the dropdown
// lists inbox entries grouped by app. All state lives in the plugin's own
// service (Service.qml); this file only renders it and forwards actions.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "components"
import "InboxLogic.js" as InboxLogic
import "ServiceBridge.js" as ServiceBridge

Panel {
  id: root
  moduleName: "araneadev.notifications"
  // Opened through `omarchy-shell shell toggle araneadev.notifications`, which
  // routes to the widget on the focused monitor; no per-instance IPC target.
  manageIpc: false

  // The Aranea bar gives widgets a service-less facade, so the service is
  // read from the plugin's shared bridge. Re-checked every second: a shell
  // reload replaces the service object.
  property var service: ServiceBridge.current()
  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      var next = ServiceBridge.current()
      if (next !== root.service) root.service = next
    }
  }
  readonly property bool available: !!(service && service.inbox)
  readonly property int count: available ? service.inbox.count : 0
  readonly property bool dnd: service ? !!service.doNotDisturb : false
  readonly property bool quiet: service ? !!service.quietHours : false
  readonly property int criticalCount: {
    if (!available) return 0
    var revision = service.inbox.revision   // re-evaluate on every inbox change
    var n = 0
    var model = service.inbox.model
    for (var i = 0; i < model.count; i++) if (model.get(i).urgency === 2) n++
    return n
  }
  // Red with the critical count when anything critical waits; otherwise mint
  // with the total; DND hides the non-critical badge.
  readonly property var badge: InboxLogic.badgeState(count, criticalCount, dnd || quiet)
  // Violet focus accent (colors.toml accent_secondary) for scheduled quiet hours.
  readonly property color focusAccent: "#7a5cff"

  property var expanded: ({})
  // The keyboard cursor follows its item (InboxLogic.rowKey), so an arrival
  // that shifts the list never redirects Enter/Delete to another entry.
  property string cursorKey: ""
  readonly property int cursor: cursorKey ? InboxLogic.indexOfKey(rows, cursorKey) : -1
  property bool confirmingClear: false
  property real now: Date.now()

  readonly property var rows: {
    if (!available) return []
    var revision = service.inbox.revision   // re-evaluate on every inbox change
    var entries = []
    var model = service.inbox.model
    for (var i = 0; i < model.count; i++) entries.push(model.get(i))
    return InboxLogic.flattenGroups(InboxLogic.groupView(InboxLogic.sortForCenter(entries), root.expanded))
  }

  function selectable(index: int): bool {
    var row = rows[index]
    return !!row && (row.kind === "entry" || row.kind === "more")
  }

  function moveCursor(delta: int): void {
    if (rows.length === 0) return
    var i = root.cursor
    for (var step = 0; step < rows.length; step++) {
      i = i < 0 ? (delta > 0 ? 0 : rows.length - 1) : (i + delta + rows.length) % rows.length
      if (selectable(i)) { root.cursorKey = InboxLogic.rowKey(rows[i]); list.positionViewAtIndex(i, ListView.Contain); return }
    }
  }

  function toggleGroup(app: string): void {
    var next = Object.assign({}, root.expanded)
    var group = null
    for (var i = 0; i < rows.length; i++) if (rows[i].kind === "group" && rows[i].app === app) group = rows[i]
    next[app] = group ? group.collapsed : true
    root.expanded = next
  }

  function activate(index: int): void {
    var row = rows[index]
    if (!row) return
    if (row.kind === "entry") service.invokeInbox(row.entry.fileName)
    else if (row.kind === "more" || row.kind === "group") toggleGroup(row.app)
  }

  function dismissAt(index: int, wholeGroup: bool): void {
    var row = rows[index]
    if (!row) return
    if (wholeGroup || row.kind === "group" || row.kind === "more") service.dismissGroup(row.app)
    else service.dismissInbox(row.entry.fileName)
  }

  function clearAll(): void {
    if (InboxLogic.needsClearConfirm(root.count) && !root.confirmingClear) {
      root.confirmingClear = true
      confirmTimer.restart()
      return
    }
    root.confirmingClear = false
    service.clearInbox()
  }

  onOpenedChanged: {
    if (opened) {
      root.now = Date.now()
      root.cursorKey = ""
      root.confirmingClear = false
    }
  }

  // The item under the cursor was dismissed: drop the cursor.
  onRowsChanged: if (root.cursorKey && root.cursor < 0) root.cursorKey = ""

  Timer { id: confirmTimer; interval: 4000; onTriggered: root.confirmingClear = false }
  Timer { interval: 30000; repeat: true; running: root.opened; onTriggered: root.now = Date.now() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: InboxLogic.bellGlyph(root.dnd || root.quiet)
    foreground: root.quiet ? root.focusAccent : root.barForeground
    dimmed: !root.available || root.count === 0
    tooltipText: root.available ? InboxLogic.tooltipText(root.count, root.criticalCount, root.dnd, root.quiet) : "Notifications unavailable"
    onPressed: function(b) {
      if (!root.available) return
      if (b === Qt.RightButton) root.service.setDoNotDisturb(!root.dnd)
      else if (b === Qt.MiddleButton) root.service.clearInbox()
      else root.toggle()
    }

    Rectangle {
      visible: root.available && root.badge.tone !== "none"
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.space(4)
      anchors.rightMargin: Style.space(2)
      height: Style.space(12)
      width: Math.max(height, badgeText.implicitWidth + Style.space(6))
      radius: height / 2
      color: root.badge.tone === "critical" ? Color.urgent : Color.notifications.countdown

      Text {
        id: badgeText
        anchors.centerIn: parent
        text: root.badge.label
        color: Color.background
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.available
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, panel.screenH * 0.6)

    FocusScope {
      anchors.fill: parent
      // Delete / Shift+Delete are not PanelKeyCatcher signals; they propagate
      // here unaccepted.
      Keys.onPressed: function(event) {
        if (event.key !== Qt.Key_Delete || root.cursor < 0) return
        root.dismissAt(root.cursor, (event.modifiers & Qt.ShiftModifier) !== 0)
        event.accepted = true
      }

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
        onActivateRequested: if (root.cursor >= 0) root.activate(root.cursor)
        onDeleteRequested: if (root.cursor >= 0) root.dismissAt(root.cursor, false)
        onCloseRequested: root.close()
        onTabRequested: function(direction) { root.switchPanel(direction) }

        ColumnLayout {
          id: content
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: Style.space(10)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              text: "Notifications"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: (root.dnd ? "DND ◉" : "DND ○")
              color: dndArea.containsMouse ? Color.notifications.countdown : Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              MouseArea {
                id: dndArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.service.setDoNotDisturb(!root.dnd)
              }
            }

            Text {
              visible: root.count > 0
              text: root.confirmingClear ? "Confirm clear (" + root.count + ")" : "Clear all"
              color: root.confirmingClear || clearAllArea.containsMouse ? Color.notifications.countdown : Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              MouseArea {
                id: clearAllArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clearAll()
              }
            }
          }

          Text {
            visible: root.quiet && InboxLogic.quietUntil(root.service ? root.service.quietHoursWindow : "") !== ""
            text: "Quiet until " + InboxLogic.quietUntil(root.service ? root.service.quietHoursWindow : "")
            color: root.focusAccent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          // Empty state.
          Column {
            visible: root.count === 0
            Layout.fillWidth: true
            Layout.topMargin: Style.space(12)
            Layout.bottomMargin: Style.space(12)
            spacing: Style.space(8)

            Image {
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(28)
              height: Style.space(28)
              source: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/branding/marks/aranea-glyph.svg"
              sourceSize.width: width * Screen.devicePixelRatio
              sourceSize.height: height * Screen.devicePixelRatio
              fillMode: Image.PreserveAspectFit
              opacity: 0.6
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "All caught up"
              color: Qt.darker(Color.popups.text, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }

          ListView {
            id: list
            visible: root.count > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, panel.screenH * 0.6 - Style.space(80))
            clip: true
            spacing: Style.space(6)
            model: root.rows
            boundsBehavior: Flickable.StopAtBounds

            delegate: Loader {
              id: rowLoader
              required property var modelData
              required property int index
              width: list.width
              sourceComponent: modelData.kind === "group" ? groupRow
                : (modelData.kind === "more" ? moreRow : entryRow)

              Component {
                id: groupRow
                RowLayout {
                  spacing: Style.space(6)
                  Text {
                    text: (rowLoader.modelData.collapsed ? "▸ " : "▾ ") + rowLoader.modelData.app + " · " + rowLoader.modelData.count
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    Layout.fillWidth: true
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleGroup(rowLoader.modelData.app)
                    }
                  }
                  Text {
                    text: "✕"
                    color: groupClose.containsMouse ? Color.notifications.countdown : Qt.darker(Color.popups.text, 1.4)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    MouseArea {
                      id: groupClose
                      anchors.fill: parent
                      anchors.margins: -Style.space(4)
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.service.dismissGroup(rowLoader.modelData.app)
                    }
                  }
                }
              }

              Component {
                id: moreRow
                Text {
                  leftPadding: Style.space(12)
                  text: "+" + rowLoader.modelData.hidden + " more"
                  color: root.cursor === rowLoader.index ? Color.notifications.countdown : Qt.darker(Color.popups.text, 1.3)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleGroup(rowLoader.modelData.app)
                  }
                }
              }

              Component {
                id: entryRow
                NotificationCard {
                  width: list.width
                  compact: true
                  selected: root.cursor === rowLoader.index
                  motionEnabled: root.service ? root.service.motionEnabled : true
                  app: rowLoader.modelData.entry.app
                  appIcon: rowLoader.modelData.entry.appIcon
                  summary: rowLoader.modelData.entry.summary
                  body: rowLoader.modelData.entry.body
                  image: rowLoader.modelData.entry.image
                  glyph: rowLoader.modelData.entry.glyph
                  urgency: rowLoader.modelData.entry.urgency
                  timestamp: rowLoader.modelData.entry.timestamp
                  timeLabel: InboxLogic.relativeTime(rowLoader.modelData.entry.timestamp, root.now)
                  cornerRadius: root.service ? root.service.cornerRadius : 0
                  fontFamily: root.bar ? root.bar.fontFamily : ""
                  onCardClicked: root.service.invokeInbox(rowLoader.modelData.entry.fileName)
                  onCloseRequested: root.service.dismissInbox(rowLoader.modelData.entry.fileName)
                  onSwipeDismissed: root.service.dismissInbox(rowLoader.modelData.entry.fileName)
                }
              }
            }
          }
        }
      }
    }
  }
}
