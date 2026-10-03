// Notification bell + center. The bell shows the inbox count; the dropdown
// lists inbox entries grouped by app. All state lives in the plugin's own
// service (Service.qml); this file only renders it and forwards actions.
// Loaded by the Aranea bar as this plugin's bar widget (manifest.json).

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
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
      if (next !== root.service)
        root.service = next
    }
  }
  // True when the service and its inbox are reachable.
  readonly property bool available: !!(service && service.inbox)
  // Number of inbox entries (0 while unavailable).
  readonly property int count: available ? service.inbox.count : 0
  // The service's Do Not Disturb state.
  readonly property bool dnd: service ? !!service.doNotDisturb : false
  // True while the service's quiet hours are active.
  readonly property bool quiet: service ? !!service.quietHours : false
  // Number of critical (urgency 2) inbox entries.
  readonly property int criticalCount: available ? InboxLogic.criticalCount(service.inbox.snapshot) : 0
  // Red with the critical count when anything critical waits; otherwise mint
  // with the total; DND hides the non-critical badge.
  readonly property var badge: InboxLogic.badgeState(count, criticalCount, dnd || quiet)
  // Violet focus accent (colors.toml accent_secondary) for scheduled quiet hours.
  readonly property color focusAccent: Aranea.DesignTokens.accentSecondary

  // Per-app expand overrides set by toggleGroup, fed to InboxLogic.groupView.
  property var expanded: ({})
  // The keyboard cursor follows its item (InboxLogic.rowKey), so an arrival
  // that shifts the list never redirects Enter/Delete to another entry.
  property string cursorKey: ""
  // Index of cursorKey's row in rows, or -1 when there is no cursor.
  readonly property int cursor: cursorKey ? InboxLogic.indexOfKey(rows, cursorKey) : -1
  // True while "Clear all" waits for its confirming click (reset after 4 s).
  property bool confirmingClear: false
  // Clock for the relative time labels: set on open, then every 30 s while open.
  property real now: Date.now()

  // Center rows: the inbox snapshot (plain copies, never live model objects)
  // sorted critical first, grouped by app and flattened into group, entry and
  // "more" rows (InboxLogic.centerRows).
  readonly property var rows: available ? InboxLogic.centerRows(service.inbox.snapshot, root.expanded) : []

  // The quiet-hours end time ("HH:MM"), or "" when there is no window or it
  // is malformed.
  readonly property string quietUntilText: InboxLogic.quietUntil(root.service ? root.service.quietHoursWindow : "")
  // The header caption: the quiet-hours text while quiet.hours is active and
  // the window parses, else "N unread" or "Nothing new" (today's quietUntil
  // text keeps its meaning; see NotificationCenterContent.qml).
  readonly property string centerCaption: root.quiet && root.quietUntilText !== "" ? ("Quiet until " + root.quietUntilText) : (root.count > 0 ? root.count + " unread" : "Nothing new")
  // NotificationCenterContent's view object (its Filament header and
  // footer): the list itself still renders as NotificationList below it,
  // pending Task 4's rework to place it in the content slot.
  readonly property var centerView: ({
      count: root.count,
      caption: root.centerCaption,
      dnd: {
        on: root.dnd,
        busy: false
      },
      clear: {
        visible: root.count > 0,
        confirming: root.confirmingClear,
        label: root.confirmingClear ? ("Confirm clear (" + root.count + ")") : "Clear all"
      },
      keyHint: "↑↓ move · enter open · del dismiss · ⇧del clear group"
    })

  // Whether the row at index can hold the keyboard cursor (entry and "more" rows).
  function selectable(index: int): bool {
    var row = rows[index]
    return !!row && (row.kind === "entry" || row.kind === "more")
  }

  // Moves the cursor by delta to the next selectable row, wrapping around, and
  // scrolls it into view.
  function moveCursor(delta: int): void {
    if (rows.length === 0)
      return
    var i = root.cursor
    for (var step = 0; step < rows.length; step++) {
      i = i < 0 ? (delta > 0 ? 0 : rows.length - 1) : (i + delta + rows.length) % rows.length
      if (selectable(i)) {
        root.cursorKey = InboxLogic.rowKey(rows[i])
        list.positionViewAtIndex(i, ListView.Contain)
        return
      }
    }
  }

  // Expands a collapsed app group, or collapses an expanded one.
  function toggleGroup(app: string): void {
    var next = Object.assign({}, root.expanded)
    var group = null
    for (var i = 0; i < rows.length; i++)
      if (rows[i].kind === "group" && rows[i].app === app)
        group = rows[i]
    next[app] = group ? group.collapsed : true
    root.expanded = next
  }

  // Expands the "+N more" row at index and puts the cursor on the first
  // entry it revealed (the more row itself is gone after the expand).
  function expandAt(index: int): void {
    var row = rows[index]
    if (!row)
      return
    toggleGroup(row.app)
    var revealed = rows[index]
    if (revealed && revealed.kind === "entry")
      root.cursorKey = InboxLogic.rowKey(revealed)
  }

  // Enter on a row: runs an entry's action, or toggles a group or "more" row.
  function activate(index: int): void {
    var row = rows[index]
    if (!row)
      return
    if (row.kind === "entry")
      service.invokeInbox(row.entry.fileName)
    else if (row.kind === "more")
      expandAt(index)
    else if (row.kind === "group")
      toggleGroup(row.app)
  }

  // Delete on a row (Shift sets wholeGroup): see InboxLogic.dismissAction.
  function dismissAt(index: int, wholeGroup: bool): void {
    var row = rows[index]
    var action = InboxLogic.dismissAction(row, wholeGroup)
    if (action === "expand")
      expandAt(index)
    else if (action === "group")
      service.dismissGroup(row.app)
    else if (action === "dismiss")
      service.dismissInbox(row.entry.fileName)
  }

  // Clears the inbox; above InboxLogic's confirm threshold the first call only
  // asks for confirmation.
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
  onRowsChanged: if (root.cursorKey && root.cursor < 0)
    root.cursorKey = ""

  Timer {
    id: confirmTimer
    interval: 4000
    onTriggered: root.confirmingClear = false
  }
  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    onTriggered: root.now = Date.now()
  }

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
    onPressed: function (b) {
      if (!root.available)
        return
      if (b === Qt.RightButton)
        root.service.setDoNotDisturb(!root.dnd)
      else if (b === Qt.MiddleButton)
        root.service.clearInbox()
      else
        root.toggle()
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
      Keys.onPressed: function (event) {
        if (event.key !== Qt.Key_Delete || root.cursor < 0)
          return
        root.dismissAt(root.cursor, (event.modifiers & Qt.ShiftModifier) !== 0)
        event.accepted = true
      }

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        onMoveRequested: function (dx, dy) {
          if (dy !== 0)
            root.moveCursor(dy)
        }
        onActivateRequested: if (root.cursor >= 0)
          root.activate(root.cursor)
        onDeleteRequested: if (root.cursor >= 0)
          root.dismissAt(root.cursor, false)
        onCloseRequested: root.close()
        onTabRequested: function (direction) {
          root.switchPanel(direction)
        }

        ColumnLayout {
          id: content
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: Style.space(10)

          NotificationCenterContent {
            Layout.fillWidth: true
            view: root.centerView
            onAction: function (name, arg) {
              if (name === "toggleDnd")
                root.service.setDoNotDisturb(!root.dnd)
              else if (name === "clearAll")
                root.clearAll()
            }
          }

          NotificationList {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(list.contentHeight, panel.screenH * 0.6 - Style.space(80))
            visible: root.count > 0
            rows: root.rows
            cursor: root.cursor
            now: root.now
            service: root.service
            bar: root.bar
            motionEnabled: root.service ? root.service.motionEnabled : true
            cornerRadius: root.service ? root.service.cornerRadius : 0
            onActivated: function (index, row) {
              root.activate(index)
            }
            onDismissed: function (index, row) {
              root.dismissAt(index, false)
            }
            onGroupToggled: function (app) {
              root.toggleGroup(app)
            }
            onGroupDismissed: function (app) {
              root.service.dismissGroup(app)
            }
          }
        }
      }
    }
  }
}
