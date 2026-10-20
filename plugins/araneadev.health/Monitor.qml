// System health monitor: failed services, disk almost full, reboot after a
// kernel update, containers exiting. Open problems are live state for the
// health dropdown (openProblems): they appear and clear with the problem.
// Rules live in HealthLogic.js; this file only runs the checks.

import QtQuick
import Quickshell.Io
import "../araneadev.shared" as Aranea
import "HealthLogic.js" as HealthLogic

Item {
  id: monitor

  // Last known problems per check; a check that errors keeps its previous
  // list until it can report again.
  property var problems: ({
      unit: [],
      disk: [],
      reboot: [],
      container: []
    })
  // Per check: true once it reported, false while it is unavailable.
  property var known: ({})
  // parseFailedUnits results per scope ("system", "user") until both arrived.
  property var unitParts: ({})
  // Alert level per mount point, fed back into diskProblems for hysteresis.
  property var diskLevels: ({})
  // Container history by name (HealthLogic DockerHistoryEntry).
  property var dockerHistory: ({})
  // Running kernel release from `uname -r`; "" until read.
  property string release: ""
  // Set by startChecks so the checks start only once.
  property bool checksStarted: false
  // Tools the item actions need; assume present until `which` says otherwise.
  property var tools: ({
      terminal: true
    })
  // Annotated open problems for the dropdown (HealthLogic.annotateProblems).
  property var openProblems: []
  // Latest df rows (HealthLogic.parseDf), shared with the metrics view.
  property var diskRows: []
  // Whether the checks start by themselves on creation; tests switch it off
  // and call the checks they need.
  property bool autoStart: true
  // The docker command (argv prefix); tests replace it with a shell function.
  property var dockerCommand: ["docker"]

  // Only backend-validated occurrences are hidden; later stops remain visible.
  property var acknowledgedContainerKeys: []
  // Backend command is overridable by isolated transport tests.
  property var acknowledgmentCommand: [Aranea.RuntimePaths.themeRoot + "/scripts/aranea-health-ack", "status"]
  // Requests queued while a validation is still running.
  property bool acknowledgmentPending: false
  // Guards asynchronous process startup as well as running reads.
  property bool acknowledgmentChecking: false
  // A changed Docker event or state file invalidates an in-flight read.
  property int acknowledgmentRevision: 0
  // Last file contents observed, so unrelated directory changes are harmless.
  property string acknowledgmentText: ""

  // Revalidate the persisted records against precise current Docker occurrences.
  function refreshAcknowledgments(): void {
    acknowledgmentRevision++
    acknowledgmentPending = true
    startAcknowledgmentRead()
  }
  // Serialize reads and replay the latest queued revision after completion.
  function startAcknowledgmentRead(): void {
    if (acknowledgmentChecking || !acknowledgmentPending)
      return
    acknowledgmentPending = false
    acknowledgmentChecking = true
    acknowledgmentsProc.revision = acknowledgmentRevision
    acknowledgmentsProc.startedSuccessfully = false
    acknowledgmentsProc.running = true
  }
  Process {
    id: acknowledgmentsProc
    // Revision captured before this read starts.
    property int revision: 0
    // Failed starts do not emit exited.
    property bool startedSuccessfully: false
    command: monitor.acknowledgmentCommand
    stdout: StdioCollector {
      id: acknowledgmentsOut
      waitForEnd: true
    }
    onStarted: acknowledgmentsProc.startedSuccessfully = true
    onRunningChanged: if (monitor.acknowledgmentChecking && !running && !acknowledgmentsProc.startedSuccessfully) {
      monitor.acknowledgmentChecking = false
      monitor.acknowledgedContainerKeys = []
      monitor.reconcileNow()
      Qt.callLater(monitor.startAcknowledgmentRead)
    }
    // Quickshell's QProcess::ExitStatus parameter is not registered with qmllint.
    // qmllint disable signal-handler-parameters
    onExited: function (code) {
      monitor.acknowledgmentChecking = false
      if (acknowledgmentsProc.revision === monitor.acknowledgmentRevision) {
        let keys = []
        if (code === 0) {
          try {
            keys = JSON.parse(acknowledgmentsOut.text).acknowledged
          } catch (_error) {}
        }
        monitor.acknowledgedContainerKeys = Array.isArray(keys) ? keys : []
        monitor.reconcileNow()
      }
      Qt.callLater(monitor.startAcknowledgmentRead)
    }
    // qmllint enable signal-handler-parameters
  }
  FileView {
    id: acknowledgmentsFile
    path: Aranea.RuntimePaths.araneaStateRoot + "/health-acknowledgments.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var next = text()
      if (next !== monitor.acknowledgmentText) {
        monitor.acknowledgmentText = next
        if (monitor.autoStart)
          monitor.refreshAcknowledgments()
      }
    }
    onLoadFailed: {
      var wasAcknowledged = monitor.acknowledgmentText !== "" || monitor.acknowledgedContainerKeys.length > 0
      monitor.acknowledgmentText = ""
      monitor.acknowledgedContainerKeys = []
      monitor.reconcileNow()
      if (wasAcknowledged && monitor.autoStart)
        monitor.refreshAcknowledgments()
    }
  }
  FileView {
    path: Aranea.RuntimePaths.araneaStateRoot
    watchChanges: true
    printErrors: false
    onFileChanged: acknowledgmentsFile.reload()
  }

  // Runs every check once and starts the docker connection (first call only).
  function startChecks(): void {
    if (checksStarted)
      return
    checksStarted = true
    checkUnits()
    checkDisk()
    checkReboot()
    startDocker()
  }

  // Replaces one check's problems, marks it known and rebuilds openProblems.
  function setProblems(check: string, list: var): void {
    var next = Object.assign({}, problems)
    next[check] = list
    problems = next
    var k = Object.assign({}, known)
    k[check] = true
    known = k
    reconcileNow()
  }

  // Marks a check unavailable (warns once per outage); its last problems stay.
  function markUnknown(check: string, reason: string): void {
    if (known[check] === false)
      return
    console.warn("health: " + check + " check unavailable: " + reason)
    var k = Object.assign({}, known)
    k[check] = false
    known = k
  }

  // Rebuilds openProblems from all checks' problems and the current tools.
  function reconcileNow(): void {
    var open = []
    for (let check in problems)
      open = open.concat(problems[check])
    openProblems = HealthLogic.filterAcknowledged(HealthLogic.annotateProblems(open, tools), acknowledgedContainerKeys)
  }

  // ---------------------------------------------------- failed units

  // Starts the system and user failed-unit queries unless already running.
  function checkUnits(): void {
    if (!systemUnits.running)
      systemUnits.running = true
    if (!userUnits.running)
      userUnits.running = true
  }

  // Collects one scope's systemctl output; once both scopes are in, sets the
  // unit problems, or marks the check unknown if either failed to parse.
  function unitResult(scope: string, text: string): void {
    var parsed = HealthLogic.parseFailedUnits(text, scope)
    var parts = Object.assign({}, unitParts)
    parts[scope] = parsed
    unitParts = parts
    if (parts.system === undefined || parts.user === undefined)
      return
    if (parts.system === null || parts.user === null) {
      markUnknown("unit", "systemctl failed")
      unitParts = ({})
      return
    }
    unitParts = ({})
    setProblems("unit", parts.system.concat(parts.user))
  }

  // Every one-shot check runs under `timeout 10`: a hung command then ends
  // with empty output, which parses as unknown.
  // Results are handled in onStreamFinished: Quickshell does not order it
  // against onExited, and a failed command's empty output already parses as
  // unknown (null).
  Process {
    id: systemUnits
    command: ["timeout", "10", "systemctl", "list-units", "--failed", "--output=json", "--no-pager"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: monitor.unitResult("system", text)
    }
  }

  Process {
    id: userUnits
    command: ["timeout", "10", "systemctl", "--user", "list-units", "--failed", "--output=json", "--no-pager"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: monitor.unitResult("user", text)
    }
  }

  // ---------------------------------------------------- disk

  // Starts df unless it is already running.
  function checkDisk(): void {
    if (!dfProc.running)
      dfProc.running = true
  }

  Process {
    id: dfProc
    // -l: local filesystems only (a stale network mount cannot hang df, and
    // sshfs/NFS usage is not this machine's disk). timeout: a hang becomes
    // "unknown" instead of freezing the check.
    command: ["timeout", "10", "df", "-l", "--output=source,target,fstype,size,used,avail,pcent", "-B1", "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs", "-x", "squashfs", "-x", "overlay"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var rows = HealthLogic.parseDf(text)
        if (!rows) {
          monitor.markUnknown("disk", "df failed")
          return
        }
        monitor.diskRows = rows
        var result = HealthLogic.diskProblems(rows, monitor.diskLevels)
        monitor.diskLevels = result.levels
        monitor.setProblems("disk", result.problems)
      }
    }
  }

  // ---------------------------------------------------- reboot

  // Reads the kernel release first if needed, then tests whether its module
  // directory still exists.
  function checkReboot(): void {
    if (!release) {
      if (!unameProc.running)
        unameProc.running = true
      return
    }
    modulesProc.command = ["test", "-d", "/usr/lib/modules/" + release]
    if (!modulesProc.running)
      modulesProc.running = true
  }

  Process {
    id: unameProc
    command: ["uname", "-r"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        monitor.release = text.trim()
        if (monitor.release)
          monitor.checkReboot()
        else
          monitor.markUnknown("reboot", "uname failed")
      }
    }
  }

  Process {
    id: modulesProc
    onExited: function (code) {
      if (code !== 0 && code !== 1) {
        monitor.markUnknown("reboot", "test failed")
        return
      }
      monitor.setProblems("reboot", HealthLogic.rebootProblem(code === 0, monitor.release))
    }
  }

  // ---------------------------------------------------- containers

  // Connects to docker (info, then ps snapshot, then the events stream)
  // unless a step is already running; retried every 30 s on failure.
  function startDocker(): void {
    if (!dockerInfo.running && !dockerPs.running && !dockerEvents.running)
      dockerInfo.running = true
  }

  // `docker info` prints the server version only when the daemon answered,
  // so a non-empty answer means docker is up (no exit-code handler needed).
  Process {
    id: dockerInfo
    command: ["timeout", "10"].concat(monitor.dockerCommand, ["info", "--format", "{{.ServerVersion}}"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.trim()) {
          monitor.dockerPsText = null
          monitor.dockerPsCode = null
          dockerPs.running = true
        } else {
          monitor.markUnknown("container", "docker not running")
          dockerRetry.restart()
        }
      }
    }
  }

  // Output of the running `docker ps`, null until it arrives.
  property var dockerPsText: null
  // Exit code of the running `docker ps`, null until it exits.
  property var dockerPsCode: null

  // On every (re)connect the current container states are the truth: they
  // cover a shell restart (empty history) and events missed while the stream
  // was down. The stream then continues from the snapshot time. Seeds only
  // once `docker ps` has both finished its output and exited (either may come
  // first); a nonzero exit (including timeout's 124) marks docker unknown and
  // leaves the existing container problems alone.
  function finishDockerPs(): void {
    if (monitor.dockerPsText === null || monitor.dockerPsCode === null)
      return
    if (monitor.dockerPsCode !== 0) {
      monitor.dockerPsText = null
      monitor.dockerPsCode = null
      monitor.markUnknown("container", "docker ps failed")
      dockerRetry.restart()
      return
    }
    var containers = HealthLogic.parseDockerPs(monitor.dockerPsText)
    monitor.dockerPsText = null
    monitor.dockerPsCode = null
    if (containers === null) {
      monitor.markUnknown("container", "docker ps failed")
      dockerRetry.restart()
      return
    }
    var now = Date.now()
    monitor.dockerHistory = HealthLogic.seedDockerHistory(monitor.dockerHistory, containers, now)
    dockerEvents.command = monitor.dockerCommand.concat(["events", "--since", String(Math.floor(now / 1000)), "--filter", "type=container", "--filter", "event=die", "--filter", "event=oom", "--filter", "event=start", "--filter", "event=destroy", "--format", "{{json .}}"])
    dockerEvents.running = true
    monitor.setProblems("container", HealthLogic.containerProblems(monitor.dockerHistory, now))
  }

  Process {
    id: dockerPs
    command: ["timeout", "10"].concat(monitor.dockerCommand, ["ps", "-a", "--format", "{{json .}}"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        monitor.dockerPsText = text
        monitor.finishDockerPs()
      }
    }
    onExited: function (code) {
      monitor.dockerPsCode = code
      monitor.finishDockerPs()
    }
  }

  Process {
    id: dockerEvents
    stdout: SplitParser {
      onRead: function (line) {
        var event = HealthLogic.parseDockerEvent(line)
        if (!event)
          return
        // A fresh lifecycle event must never inherit an old dismissal while
        // its exact Docker occurrence is being checked asynchronously.
        monitor.acknowledgedContainerKeys = monitor.acknowledgedContainerKeys.filter(function (key) {
          return key !== "container:" + event.name
        })
        monitor.refreshAcknowledgments()
        var now = Date.now()
        monitor.dockerHistory = HealthLogic.recordDockerEvent(monitor.dockerHistory, event, now)
        monitor.setProblems("container", HealthLogic.containerProblems(monitor.dockerHistory, now))
      }
    }
    onExited: {
      monitor.markUnknown("container", "docker events stream ended")
      dockerRetry.restart()
    }
  }

  Timer {
    id: dockerRetry
    interval: 30000
    onTriggered: monitor.startDocker()
  }

  // ---------------------------------------------------- schedule

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: {
      monitor.checkUnits()
      // Restart-loop windows drain with time, not only with events.
      if (monitor.known.container === true) {
        let now = Date.now()
        monitor.dockerHistory = HealthLogic.pruneDockerHistory(monitor.dockerHistory, now)
        monitor.setProblems("container", HealthLogic.containerProblems(monitor.dockerHistory, now))
        monitor.refreshAcknowledgments()
      }
    }
  }
  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: monitor.checkDisk()
  }
  Timer {
    interval: 300000
    repeat: true
    running: true
    onTriggered: monitor.checkReboot()
  }

  Component.onCompleted: {
    if (!monitor.autoStart)
      return
    terminalProbe.running = true
    refreshAcknowledgments()
    startChecks()
  }

  Process {
    id: terminalProbe
    command: ["which", "xdg-terminal-exec"]
    onExited: function (code) {
      monitor.tools = ({
          terminal: code === 0
        })
      monitor.reconcileNow()
    }
  }
}
