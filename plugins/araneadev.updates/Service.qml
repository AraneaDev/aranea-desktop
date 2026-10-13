// Read-only update status collection; installation stays with the host updater.
import QtQuick
import Quickshell.Io
import "../araneadev.shared" as Aranea
import "UpdateLogic.js" as UpdateLogic

Item {
  id: root

  // Test-only status override.
  property var testStatus: null
  // Whether automatic refresh is enabled.
  property bool autoStart: true
  // Collector path follows the active theme, like other Aranea adapters.
  property string adapterPath: Aranea.RuntimePaths.themeRoot + "/scripts/aranea-update-status"
  // Parsed and merged update status.
  property var status: UpdateLogic.parseStatus({
    updates: []
  })
  // Refresh activity drives the panel's busy state.
  property bool checking: false
  // Failed launches never emit exited; distinguish them from a normal exit.
  property bool processStarted: false

  onTestStatusChanged: if (testStatus !== null)
    applyStatus(testStatus)

  // Retain the last valid result when any source check is unavailable.
  function applyStatus(raw) {
    var next = raw && raw.error ? raw : UpdateLogic.parseStatus(raw)
    status = UpdateLogic.mergeRefresh(status, next, Date.now())
  }

  // Never overlap checks or run a live command with a test status override.
  function refresh() {
    if (testStatus !== null) {
      applyStatus(testStatus)
      return
    }
    if (root.checking)
      return
    root.checking = true
    root.processStarted = false
    updateProc.running = true
  }

  Component.onCompleted: {
    if (testStatus !== null)
      applyStatus(testStatus)
    else if (autoStart)
      refresh()
  }

  Process {
    id: updateProc
    command: [root.adapterPath]
    stdout: StdioCollector {
      id: updateStdout
      waitForEnd: true
    }
    onStarted: root.processStarted = true
    onRunningChanged: if (root.checking && !running && !root.processStarted) {
      root.checking = false
      root.applyStatus({
        error: "update check could not start"
      })
    }
    onExited: function (exitCode, exitStatus) {
      void exitStatus
      root.checking = false
      root.applyStatus(UpdateLogic.statusFromOutput(updateStdout.text, exitCode))
    }
  }

  Timer {
    interval: 3600000
    repeat: true
    running: root.autoStart
    onTriggered: root.refresh()
  }
}
