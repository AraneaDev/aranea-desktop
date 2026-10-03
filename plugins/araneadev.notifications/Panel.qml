// Notification bell + center. The bell shows the inbox count; the dropdown
// lists inbox entries grouped by app, drawn in the shared Aranea keyboard
// frame with a keyboard-only cursor. All state lives in the plugin's own
// service (Service.qml); this file only renders it and forwards actions.
// Loaded by the Aranea bar as this plugin's bar widget (manifest.json).

import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "InboxLogic.js" as InboxLogic
import "../araneadev.shared/CursorLogic.js" as CursorLogic
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

  // ---- The keyboard cursor. It moves through stops (InboxLogic.centerStops):
  // the DND switch, every entry and "+N more" row, then the Clear pill. Up
  // and Down step through them, held at both ends; Left and Right only
  // reveal. The cursor follows its stop's key (InboxLogic.rowKey, "dnd" or
  // "clear"), so an arrival that re-sorts the list never redirects Enter or
  // Delete to another entry. When its key vanishes it hides, except right
  // after a keyboard Delete, where it stays shown on the neighbour
  // (the decision is InboxLogic.followRemoval's; see onCursorStopChanged).
  // The key of the stop the cursor is on, or "" for none.
  property string cursorKey: ""
  // True while the keyboard drives the cursor; any pointer use clears it.
  // The outline shows only then; the first navigation key only reveals.
  property bool keyboardCursor: false
  // The stop the cursor was last on, so a cursor whose key vanished is
  // revealed near where it was, or (InboxLogic.followRemoval) is the
  // neighbour a keyboard Delete lands on; -1 for none.
  property int lastStop: -1
  // The key a keyboard Delete is removing (deleteCursor arms it with the
  // cursor's own key before the row leaves), read by
  // InboxLogic.followRemoval so the next stops change lands the cursor on
  // its neighbour instead of hiding it; "" when the next loss should hide
  // it as usual (a pointer dismiss or a background update).
  property string pendingRemovalKey: ""
  // True while "Clear all" waits for its confirming click (reset after 4 s).
  property bool confirmingClear: false
  // Clock for the relative time labels: set on open, then every 30 s while open.
  property real now: Date.now()
  // The pending Do Not Disturb change (InboxLogic.dndClick / dndEcho):
  // the switch shows the new state at once and pulses until the service
  // echoes it; clicks while it waits are queued, the last one wins.
  property var dndPending: InboxLogic.dndIdle()

  // Center rows: the inbox snapshot (plain copies, never live model objects)
  // sorted critical first, grouped by app and flattened into group, entry and
  // "more" rows (InboxLogic.centerRows).
  readonly property var rows: available ? InboxLogic.centerRows(service.inbox.snapshot, root.expanded) : []
  // The cursor's stops, top to bottom (InboxLogic.centerStops).
  readonly property var stops: InboxLogic.centerStops(root.rows, root.count > 0)
  // Index of cursorKey's stop, or -1 when there is no cursor or it vanished.
  readonly property int cursorStop: InboxLogic.stopIndex(root.stops, root.cursorKey)
  // Index of the cursor's row in rows, or -1 when it is not on a row.
  readonly property int cursor: root.cursorStop >= 0 ? root.stops[root.cursorStop].index : -1
  // Whether the cursor's outline shows: keyboard-driven and on a stop.
  readonly property bool cursorShown: root.keyboardCursor && root.cursorStop >= 0

  // The quiet-hours end time ("HH:MM"), or "" when there is no window or it
  // is malformed.
  readonly property string quietUntilText: InboxLogic.quietUntil(root.service ? root.service.quietHoursWindow : "")
  // The header caption (InboxLogic.centerCaption): the quiet-hours text
  // while quiet hours are active and the window parses, else "N unread" or
  // "Nothing new".
  readonly property string centerCaption: InboxLogic.centerCaption(root.count, root.quiet, root.quietUntilText)
  // NotificationCenterContent's view object (its Filament header and
  // footer; the list sits in its slot).
  readonly property var centerView: ({
      count: root.count,
      caption: root.centerCaption,
      glyph: InboxLogic.bellGlyph(root.dnd || root.quiet),
      dnd: InboxLogic.dndView(root.dndPending, root.dnd),
      clear: {
        visible: root.count > 0,
        confirming: root.confirmingClear,
        label: root.confirmingClear ? ("Confirm clear (" + root.count + ")") : "Clear all"
      },
      keyHint: InboxLogic.centerKeyHint(root.count)
    })

  // Puts the cursor on stop INDEX and scrolls its row into view.
  function placeCursor(index: int): void {
    var stop = root.stops[index]
    if (!stop)
      return
    root.cursorKey = stop.key
    if (stop.index >= 0)
      list.positionViewAtIndex(stop.index, ListView.Contain)
  }

  // Up or Down (DELTA -1 or +1; 0 for Left or Right): the first key after
  // opening, after pointer use or after the cursor's key vanished only
  // reveals the cursor; later ones step through the stops.
  function moveCursor(delta: int): void {
    list.disarmPointer()
    centerContent.disarmPointer()
    var revealing = !root.cursorShown
    root.keyboardCursor = true
    if (revealing) {
      if (root.cursorStop < 0)
        root.placeCursor(InboxLogic.revealStop(root.stops, root.lastStop))
      else
        root.placeCursor(root.cursorStop)
      return
    }
    if (delta !== 0)
      root.placeCursor(InboxLogic.moveStop(root.stops, root.cursorStop, delta))
  }

  // Whether a key may act on the cursor (CursorLogic.pressIntent): with no
  // cursor it does nothing, a hidden one is only revealed.
  function keyMayAct(): bool {
    list.disarmPointer()
    centerContent.disarmPointer()
    var intent = CursorLogic.pressIntent(root.cursorStop >= 0, root.keyboardCursor)
    if (intent === "ignore")
      return false
    root.keyboardCursor = true
    return intent === "act"
  }

  // Enter or Space: opens an entry, expands a "+N more" row, toggles DND or
  // presses Clear, whichever the cursor is on.
  function activateCursor(): void {
    if (!root.keyMayAct())
      return
    if (root.cursorKey === "dnd")
      root.toggleDnd()
    else if (root.cursorKey === "clear")
      root.clearAll()
    else if (root.cursor >= 0)
      root.activate(root.cursor)
  }

  // Delete (Shift sets wholeGroup) or x: on a row, see dismissAt; nothing on
  // the DND switch or the Clear pill. An actual removal (not a "+N more"
  // expand) arms pendingRemovalKey, so the cursor stays shown on its
  // neighbour once the row is gone (InboxLogic.followRemoval).
  function deleteCursor(wholeGroup: bool): void {
    if (!root.keyMayAct() || root.cursor < 0)
      return
    var action = InboxLogic.dismissAction(root.rows[root.cursor], wholeGroup)
    if (action === "dismiss" || action === "group")
      root.pendingRemovalKey = root.cursorKey
    root.dismissAt(root.cursor, wholeGroup)
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
  // entry it revealed (the more row itself is gone after the expand). The
  // more row's key vanishing hides the cursor; a keyboard-shown cursor is
  // shown again on the revealed entry, a pointer-placed one stays hidden.
  function expandAt(index: int): void {
    var row = rows[index]
    if (!row)
      return
    var shown = root.keyboardCursor
    toggleGroup(row.app)
    var revealed = rows[index]
    if (revealed && revealed.kind === "entry") {
      root.cursorKey = InboxLogic.rowKey(revealed)
      root.keyboardCursor = shown
    }
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

  // Applies a DND step RESULT ({state, send}, InboxLogic.dndClick or
  // dndEcho): stores the state first, so an echo that arrives during the
  // send (the service writes synchronously today) sees it, then sends.
  function applyDnd(result: var): void {
    root.dndPending = result.state
    if (result.send !== null && root.service)
      root.service.setDoNotDisturb(result.send)
    // Still waiting after the send: give the echo a deadline.
    if (root.dndPending.target === null)
      dndTimeout.stop()
    else if (result.send !== null)
      dndTimeout.restart()
  }

  // The DND switch was clicked or activated.
  function toggleDnd(): void {
    if (root.service)
      root.applyDnd(InboxLogic.dndClick(root.dndPending, root.dnd))
  }

  // A NotificationList action (open, dismiss, toggle, clearGroup, hover)
  // with ARG {index, key}, checked again against the current rows. Pointer
  // use hides the keyboard cursor; a hover only moves the hidden cursor
  // onto the row (no fill, no outline), so the next key reveals it there.
  function listAction(name: string, arg: var): void {
    var row = root.rows[arg.index]
    if (!row || InboxLogic.rowKey(row) !== arg.key)
      return
    root.keyboardCursor = false
    if (name === "open")
      root.activate(arg.index)
    else if (name === "dismiss")
      root.dismissAt(arg.index, false)
    else if (name === "toggle")
      root.toggleGroup(row.app)
    else if (name === "clearGroup")
      root.service.dismissGroup(row.app)
    else if (name === "hover" && InboxLogic.stopIndex(root.stops, arg.key) >= 0)
      root.cursorKey = arg.key
  }

  // A fresh open shows no cursor until the first navigation key.
  onOpenedChanged: {
    root.keyboardCursor = false
    root.cursorKey = ""
    root.lastStop = -1
    root.pendingRemovalKey = ""
    if (opened) {
      root.now = Date.now()
      root.confirmingClear = false
    }
  }

  // The cursor's stop recomputed (a removal, a re-sort, or the cursor's own
  // key moving). InboxLogic.followRemoval is the single source of truth for
  // what happens next: it lands the cursor on CursorLogic.afterRemoval's
  // neighbour after a keyboard removal (pendingRemovalKey), hides it on any
  // other vanish (a pointer dismiss or a background update), and otherwise
  // keeps it exactly as shown, dropping a stale pendingRemovalKey once the
  // cursor's own key survives.
  onCursorStopChanged: {
    var next = InboxLogic.followRemoval(root.stops, root.pendingRemovalKey, root.cursorKey, root.lastStop, root.keyboardCursor)
    root.pendingRemovalKey = next.pendingKey
    root.cursorKey = next.key
    root.keyboardCursor = next.shown
    var stop = InboxLogic.stopIndex(root.stops, next.key)
    if (stop >= 0)
      root.lastStop = stop
  }

  // The service echoed a DND change (or something else changed it).
  onDndChanged: root.applyDnd(InboxLogic.dndEcho(root.dndPending, root.dnd))

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
  // Gives up on a DND change the service never echoed: the switch shows
  // the service's state again.
  Timer {
    id: dndTimeout
    interval: 3000
    onTriggered: root.dndPending = InboxLogic.dndIdle()
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

  Aranea.KeyboardPanelFrame {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.available
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(centerContent.implicitHeight, panel.screenH * 0.6)
    onCloseRequested: root.close()
    onTabRequested: function (direction) {
      list.disarmPointer()
      centerContent.disarmPointer()
      root.switchPanel(direction)
    }
    onMoveRequested: function (dx, dy) {
      root.moveCursor(dy)
    }
    onActivateRequested: root.activateCursor()
    // "x", as the stock catcher sends it.
    onDeleteRequested: root.deleteCursor(false)
    // Delete and Shift+Delete are not catcher signals; they arrive here.
    onUnhandledKey: function (event) {
      if (event.key !== Qt.Key_Delete)
        return
      root.deleteCursor((event.modifiers & Qt.ShiftModifier) !== 0)
      event.accepted = true
    }

    NotificationCenterContent {
      id: centerContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      view: root.centerView
      dndCursor: root.cursorShown && root.cursorKey === "dnd"
      clearCursor: root.cursorShown && root.cursorKey === "clear"
      onAction: function (name, arg) {
        root.keyboardCursor = false
        if (name === "toggleDnd")
          root.toggleDnd()
        else if (name === "clearAll")
          root.clearAll()
      }

      NotificationList {
        id: list
        width: parent.width
        // Capped so the header and the footer stay inside the card: the
        // card's largest content height (the 60% cap, less its padding
        // and border) less the space above and below the list.
        height: root.count > 0 ? InboxLogic.listHeight(list.contentHeight, panel.fittedContentHeight(panel.screenH, panel.screenH * 0.6) - panel.verticalContentInset, centerContent.slotTop, centerContent.footerHeight) : 0
        visible: root.count > 0
        rows: root.rows
        // The mint outline: only while the keyboard drives the cursor and
        // it is on a row.
        cursor: ({
            active: root.cursorShown && root.cursor >= 0,
            index: root.cursor
          })
        headerHeight: centerContent.slotTop
        now: root.now
        service: root.service
        bar: root.bar
        motionEnabled: root.service ? root.service.motionEnabled : true
        cornerRadius: root.service ? root.service.cornerRadius : 0
        // The list's height moves the Clear pill below it.
        onHeightChanged: centerContent.noteLayoutChange()
        onAction: function (name, arg) {
          root.listAction(name, arg)
        }
      }
    }
  }
}
