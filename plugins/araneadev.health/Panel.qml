// Health bar widget (the plugin's "barWidget" entry point, placed in the
// Aranea bar): a status icon plus a dropdown with open problems and live
// metrics. State lives in the health service (Service.qml), read through
// HealthBridge.js because the Aranea bar gives widgets a service-less facade.

import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "HealthBridge.js" as HealthBridge
import "HealthLogic.js" as HealthLogic
import "HealthSummaryLogic.js" as SummaryLogic

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
  // Service severity; availability always takes precedence in the summary.
  readonly property string status: available ? service.status : "healthy"
  // The service's annotated open problems, [] while unavailable.
  readonly property var problems: available ? service.problems : []
  // The service's Metrics.qml, or null while unavailable.
  readonly property var m: available ? service.metrics : null
  // Colour of the "attention" status and levels.
  readonly property color amber: Aranea.DesignTokens.attention
  // Icon colour for the current status.
  readonly property color statusColor: !available ? Util.alpha(Aranea.DesignTokens.foreground, 0.55) : status === "critical" ? Aranea.DesignTokens.urgent : (status === "attention" ? amber : Aranea.DesignTokens.ceremony)
  // Key of the cursor's problem or disclosure heading ("" for none);
  // rows re-sort as checks run, so the cursor follows the problem, not a
  // position. Only the keyboard (and a click) places it; hover never does.
  property string cursorKey: ""
  // True while the keyboard drives the cursor; any pointer use clears it.
  // The mint outline shows only then, and the first key after opening or
  // after pointer use only reveals it.
  property bool keyboardCursor: false
  // Disclosure headings are keyed stops after all actionable problems.
  property bool resourcesExpanded: false
  // Host-owned Processes expansion state.
  property bool processesExpanded: false
  // Problem keys followed by the two disclosure heading keys.
  readonly property var keyboardStops: SummaryLogic.keyboardStops(root.problems)
  // Index of the cursor key among all visible keyboard stops.
  readonly property int cursor: HealthLogic.indexOfKey(root.keyboardStops, root.cursorKey)
  // Toggles resource details and restores internal focus on collapse.
  function toggleResources(): void {
    if (root.resourcesExpanded && root.cursorKey.indexOf("details:resources:") === 0)
      root.cursorKey = "details:resources"
    root.resourcesExpanded = !root.resourcesExpanded
    dropdown.noteLayoutChange()
    Qt.callLater(dropdown.ensureCursorVisible)
  }

  // Toggles process details and restores internal focus on collapse.
  function toggleProcesses(): void {
    if (root.processesExpanded && root.cursorKey.indexOf("details:processes:") === 0)
      root.cursorKey = "details:processes"
    root.processesExpanded = !root.processesExpanded
    dropdown.noteLayoutChange()
    Qt.callLater(dropdown.ensureCursorVisible)
  }

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
    var next = HealthLogic.cursorMove(root.keyboardStops, root.cursorKey, root.keyboardCursor, dy)
    root.cursorKey = next.key
    root.keyboardCursor = next.keyboard
  }

  // Enter or Space: reveals a cursor the keyboard is not showing (on the
  // first problem after opening), else opens the cursor's problem
  // (HealthLogic.cursorPress).
  function activateCursor(): void {
    var press = HealthLogic.cursorPress(root.keyboardStops, root.cursorKey, root.keyboardCursor)
    root.cursorKey = press.key
    root.keyboardCursor = press.keyboard
    if (!press.row)
      return
    if (press.key === "details:resources")
      root.toggleResources()
    else if (press.key === "details:processes")
      root.toggleProcesses()
    else
      root.runRow(HealthLogic.keyedProblem(root.problems, HealthLogic.indexOfKey(root.problems, press.key), press.key))
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
    if (opened && service && !countedService) {
      countedService = service
      service.panelOpened()
    } else if (!opened) {
      releaseCount()
    }
    if (opened && root.available) {
      service.metrics.refreshSlow()
      service.monitor.checkDisk()
    }
    root.cursorKey = ""
    root.keyboardCursor = false
    if (!opened) {
      root.resourcesExpanded = false
      root.processesExpanded = false
      dropdown.scrollViewport.contentY = 0
    }
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
      if (b === Qt.RightButton && root.available)
        Util.execArgv(["xdg-terminal-exec", "btop"])
      else
        root.toggle()
    }
  }

  // The keyboard frame retains host-owned lifecycle, cursor and expansion.
  // The view keeps primary state above a capped body and a fixed key hint.
  Aranea.KeyboardPanelFrame {
    id: panel
    refined: true
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(dropdown.implicitHeight, Style.space(720))
    onCloseRequested: root.close()
    onTabRequested: function (direction) {
      dropdown.disarmPointer()
      root.switchPanel(direction)
    }
    onMoveRequested: function (dx, dy) {
      dropdown.disarmPointer()
      root.moveCursor(dy)
    }
    onActivateRequested: {
      dropdown.disarmPointer()
      root.activateCursor()
    }

    HealthDropdown {
      id: dropdown
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      available: root.available
      status: root.status
      problems: root.problems
      metrics: root.m
      active: root.opened
      cursorKey: root.cursorKey
      keyboardCursor: root.keyboardCursor
      resourcesExpanded: root.resourcesExpanded
      processesExpanded: root.processesExpanded
      maxContentHeight: Math.max(0, Math.min(Style.space(720), panel.availableCardHeight) - panel.verticalContentInset)
      onProblemActivated: function (index, key) {
        root.activateRow(index, key)
      }
      onResourcesToggleRequested: {
        root.keyboardCursor = false
        root.cursorKey = "details:resources"
        root.toggleResources()
      }
      onProcessesToggleRequested: {
        root.keyboardCursor = false
        root.cursorKey = "details:processes"
        root.toggleProcesses()
      }
    }
  }
}
