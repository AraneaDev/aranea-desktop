// Health bar widget (the plugin's "barWidget" entry point, placed in the
// Aranea bar): a status icon plus a dropdown with open problems and live
// metrics. State lives in the health service (Service.qml), read through
// HealthBridge.js because the Aranea bar gives widgets a service-less facade.

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "HealthBridge.js" as HealthBridge
import "HealthLogic.js" as HealthLogic

Panel {
  id: root
  moduleName: "araneadev.health"
  manageIpc: false

  // The published health service, or null; re-polled every second so a
  // reloaded service is picked up.
  property var service: HealthBridge.current()
  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      var next = HealthBridge.current()
      if (next !== root.service)
        root.service = next
    }
  }

  // True while a service with metrics is published.
  readonly property bool available: !!(service && service.metrics)
  // The service's status, "healthy" while unavailable.
  readonly property string status: available ? service.status : "healthy"
  // The service's annotated open problems, [] while unavailable.
  readonly property var problems: available ? service.problems : []
  // The service's Metrics.qml, or null while unavailable.
  readonly property var m: available ? service.metrics : null
  // Colour of the "attention" status and levels.
  readonly property color amber: Aranea.DesignTokens.attention
  // Icon colour for the current status.
  readonly property color statusColor: status === "critical" ? Aranea.DesignTokens.urgent : (status === "attention" ? amber : Aranea.DesignTokens.ceremony)
  // Key of the cursor's problem (HealthLogic.problemKey, "" for none);
  // rows re-sort as checks run, so the cursor follows the problem, not a
  // position. The pointer places it too, without showing it.
  property string cursorKey: ""
  // True while the keyboard drives the cursor; any pointer use clears it.
  // The mint outline shows only then, and the first key after opening or
  // after pointer use only reveals it.
  property bool keyboardCursor: false
  // Index of cursorKey's row in problems, -1 when none.
  readonly property int cursor: HealthLogic.indexOfKey(root.problems, root.cursorKey)
  // A problem that went away takes the cursor with it (after the change
  // settles, so cursor never re-evaluates inside its own change signal).
  onCursorChanged: if (root.cursor < 0 && root.cursorKey)
    Qt.callLater(root.dropLostCursor)

  // Clears cursorKey when it no longer names an open problem.
  function dropLostCursor(): void {
    if (root.cursor < 0)
      root.cursorKey = ""
  }

  // Moves the keyboard cursor DY rows, wrapping; the first key after
  // opening or after pointer use only reveals it (HealthLogic.cursorMove).
  function moveCursor(dy: int): void {
    var next = HealthLogic.cursorMove(root.problems, root.cursorKey, root.keyboardCursor, dy)
    root.cursorKey = next.key
    root.keyboardCursor = next.keyboard
  }

  // Enter or Space: reveals a cursor the keyboard is not showing, else
  // opens the cursor's problem (HealthLogic.cursorPress).
  function activateCursor(): void {
    var press = HealthLogic.cursorPress(root.problems, root.cursorKey, root.keyboardCursor)
    root.keyboardCursor = press.keyboard
    root.runRow(press.row)
  }

  // A settled click on row INDEX, which held KEY: opens that problem,
  // refused when the row no longer carries KEY.
  function activateRow(index: int, key: string): void {
    root.keyboardCursor = false
    var row = HealthLogic.keyedProblem(root.problems, index, key)
    if (!row)
      return
    root.cursorKey = key
    root.runRow(row)
  }

  // The pointer really moved onto row INDEX: the cursor goes there,
  // hidden, so a following key reveals it in place.
  function hoverRow(index: int): void {
    root.keyboardCursor = false
    root.cursorKey = HealthLogic.problemKey(root.problems[index])
  }

  // Runs a problem row's click command, if it has one.
  function runRow(row): void {
    if (row && row.execArgv && row.execArgv.length)
      Util.execArgv(row.execArgv)
  }

  // Counted per panel, so switching the dropdown between monitors (the host
  // closes one as it opens the other) never leaves sampling off.
  // The service this panel told panelOpened(), or null.
  property var countedService: null
  // Tells the counted service this panel closed and forgets it.
  function releaseCount(): void {
    if (countedService) {
      try {
        countedService.panelClosed()
      } catch (e) {
        // The old service may already be gone (a reload replaced it).
      }
    }
    countedService = null
  }

  // A reloaded health service replaces the one this open panel counted
  // itself on: move the count over so TOP sampling stays on.
  onServiceChanged: if (root.opened) {
    root.releaseCount()
    if (root.service) {
      root.countedService = root.service
      root.service.panelOpened()
    }
  }
  Component.onDestruction: releaseCount()

  onOpenedChanged: {
    // Summoned (IPC/keybind) while the service is missing: the card cannot
    // show, so do not stay "open" and swallow the next click.
    if (opened && !root.available) {
      root.close()
      return
    }
    if (opened && service && !countedService) {
      countedService = service
      service.panelOpened()
    } else if (!opened) {
      releaseCount()
    }
    if (opened && service) {
      service.metrics.refreshSlow()
      service.monitor.checkDisk()
    }
    root.cursorKey = ""
    root.keyboardCursor = false
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String.fromCodePoint(0xf05f6)
    foreground: root.available ? root.statusColor : root.barForeground
    dimmed: !root.available
    tooltipText: !root.available ? "Health unavailable" : (root.problems.length === 0 ? "Healthy" : root.problems.length + (root.problems.length === 1 ? " problem" : " problems") + (root.problems.filter(function (p) {
          return p.urgency === 2
        }).length > 0 ? " · " + root.problems.filter(function (p) {
          return p.urgency === 2
        }).length + " critical" : ""))
    onPressed: function (b) {
      if (!root.available)
        return
      if (b === Qt.RightButton)
        Util.execArgv(["xdg-terminal-exec", "btop"])
      else
        root.toggle()
    }
  }

  // The dropdown in the shared keyboard frame: the header (glyph,
  // hostname, uptime), the problems, the resources, the top processes and a
  // key hint. Up and down walk the problems; Enter or Space opens one.
  Aranea.KeyboardPanelFrame {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.available
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)
    onCloseRequested: root.close()
    onTabRequested: function (direction) {
      problemsSection.disarmPointer()
      root.switchPanel(direction)
    }
    onMoveRequested: function (dx, dy) {
      problemsSection.disarmPointer()
      root.moveCursor(dy)
    }
    onActivateRequested: {
      problemsSection.disarmPointer()
      root.activateCursor()
    }

    ColumnLayout {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(10)

      Aranea.DropdownHeader {
        Layout.fillWidth: true
        glyph: String.fromCodePoint(0xf05f6)
        glyphColor: root.statusColor
        title: root.m ? root.m.hostname : ""
        caption: root.m ? root.m.uptime : ""
      }

      Hairline {}

      HealthProblemsSection {
        id: problemsSection
        Layout.fillWidth: true
        problems: root.problems
        // Growth anywhere in the card can move the rows (a side or bottom
        // bar centres it or grows it upwards): it settles their clicks.
        hostContentHeight: content.implicitHeight
        cursor: HealthLogic.outlineIndex(root.problems, root.cursorKey, root.keyboardCursor)
        amber: root.amber
        onProblemActivated: function (index, key) {
          root.activateRow(index, key)
        }
        onRowHovered: function (index) {
          root.hoverRow(index)
        }
      }

      Hairline {}

      HealthResourceSection {
        Layout.fillWidth: true
        metrics: root.m
        active: root.opened
      }

      Hairline {
        visible: processSection.visible
      }

      HealthProcessSection {
        id: processSection
        visible: !!(root.m && (root.m.topProcs.cpu.length > 0 || root.m.topProcs.mem.length > 0))
        Layout.fillWidth: true
        cpuProcesses: root.m && root.m.topProcs ? root.m.topProcs.cpu : []
        memoryProcesses: root.m && root.m.topProcs ? root.m.topProcs.mem : []
      }

      Text {
        objectName: "keyHint"
        Layout.fillWidth: true
        text: "↑↓ move · enter open · tab next"
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.3)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  // The hairline between sections.
  component Hairline: Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: Math.max(1, Style.spacing.hairline)
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
  }
}
