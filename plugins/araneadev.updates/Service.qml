// Update status service and updater process coordination.
import QtQuick
import Quickshell
import Quickshell.Io
import "UpdateLogic.js" as UpdateLogic

Item {
  id: root

  // Test-only status override.
  property var testStatus: null
  // Whether automatic refresh is enabled.
  property bool autoStart: true
  // Parsed and merged update status.
  property var status: UpdateLogic.parseStatus({
    updates: []
  })
  // State directory containing the reboot marker.
  property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
  // Path to the reboot-required marker.
  readonly property string rebootPath: stateHome + "/omarchy/reboot-required"
  // Raw updater output.
  property string updateOutput: ""
  // Whether the update process has completed.
  property bool updateFinished: false
  // Whether the reboot marker check has completed.
  property bool rebootFinished: false
  // Whether the update process failed.
  property bool updateFailed: false

  onTestStatusChanged: if (testStatus !== null)
    applyStatus(testStatus)

  // Convert updater output into update rows.
  function statusFromOutput(text) {
    var lines = String(text || "").split(/\r?\n/).map(function (line) {
      return line.trim()
    }).filter(function (line) {
      return line && line !== "Omarchy is up to date"
    })
    return {
      updates: lines.map(function (line) {
        return {
          source: line.split(/\s+/)[0] || "system",
          name: line
        }
      }),
      rebootRequired: false
    }
  }

  // Apply a raw or already-error status to the current state.
  function applyStatus(raw) {
    var next = raw && raw.error ? raw : UpdateLogic.parseStatus(raw)
    status = UpdateLogic.mergeRefresh(status, next, Date.now())
  }

  // Merge process results after both checks finish.
  function finishRefresh() {
    if (!updateFinished || !rebootFinished)
      return
    var next = statusFromOutput(updateOutput)
    next.rebootRequired = !updateFailed && rebootExitCode === 0
    if (updateFailed)
      next = {
        error: "update check unavailable"
      }
    applyStatus(next)
    updateFinished = false
    rebootFinished = false
    updateOutput = ""
    updateFailed = false
  }

  // Start an update and reboot-marker refresh.
  function refresh() {
    if (testStatus !== null) {
      applyStatus(testStatus)
      return
    }
    if (updateProc.running || rebootProc.running)
      return
    updateFinished = false
    rebootFinished = false
    updateFailed = false
    updateProc.running = true
    rebootProc.running = true
  }

  Component.onCompleted: {
    if (testStatus !== null)
      applyStatus(testStatus)
    else if (autoStart)
      refresh()
  }

  Process {
    id: updateProc
    command: ["omarchy-update-available"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateOutput = text
    }
    onExited: function (exitCode, exitStatus) {
      void exitStatus
      root.updateFailed = exitCode !== 0 && root.updateOutput.trim() === ""
      root.updateFinished = true
      root.finishRefresh()
    }
  }

  // Exit status from the reboot marker process.
  property int rebootExitCode: 1

  Process {
    id: rebootProc
    command: ["test", "-f", root.rebootPath]
    onExited: function (exitCode, exitStatus) {
      void exitStatus
      root.rebootExitCode = exitCode
      root.rebootFinished = true
      root.finishRefresh()
    }
  }

  Timer {
    interval: 21600000
    repeat: true
    running: root.autoStart
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
