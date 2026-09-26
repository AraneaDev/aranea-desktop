// System health monitor: failed services, disk almost full, reboot after a
// kernel update, containers exiting. Each open problem is one live inbox item
// (sourceKey) that updates in place and disappears when the problem clears;
// dismissing it mutes the problem until it clears. Rules live in
// HealthLogic.js; this file only runs the checks and applies decisions.

import QtQuick
import Quickshell
import Quickshell.Io
import "HealthLogic.js" as HealthLogic
import "../araneadev.notifications/ServiceBridge.js" as NotificationsBridge

Item {
  id: monitor

  property var service: null
  readonly property string stateRoot: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/aranea/"
  readonly property string muteFilePath: stateRoot + "health.json"

  // Last known problems per check; a check that errors keeps its previous
  // list and stays out of knownChecks, so it never resolves anything.
  property var problems: ({ unit: [], disk: [], reboot: [], container: [] })
  property var known: ({})
  property var unitParts: ({})
  property var diskLevels: ({})
  property var dockerHistory: ({})
  property var muted: []
  property var expected: []
  property string release: ""
  property bool muteLoaded: false
  property bool expectedSeeded: false
  property bool checksStarted: false
  // Tools the item actions need; assume present until `which` says otherwise.
  property var tools: ({ terminal: true })
  // Annotated open problems for the dropdown (HealthLogic.annotateProblems).
  property var openProblems: []
  // Latest df rows (HealthLogic.parseDf), shared with the metrics view.
  property var diskRows: []

  // The notifications plugin publishes its service on a shared bridge; poll
  // it so a reload (or a late start) of that plugin is picked up.
  Timer {
    interval: 5000; repeat: true; running: true; triggeredOnStart: true
    onTriggered: {
      var next = NotificationsBridge.current()
      // Until its inbox has read the directory, the service cannot say which
      // items already exist; taking it earlier would duplicate them.
      if (next && !(next.inbox && next.inbox.loadedOnce)) next = null
      if (next !== monitor.service) {
        monitor.service = next
        monitor.expectedSeeded = false
        monitor.reconcileNow()
      }
    }
  }

  // Without a notifications service the checks still start after a grace
  // period; items are posted once the service appears.
  Timer { id: startGrace; interval: 10000; running: true; onTriggered: monitor.startChecks() }

  function startChecks(): void {
    if (checksStarted) return
    checksStarted = true
    checkUnits()
    checkDisk()
    checkReboot()
    startDocker()
  }

  function setProblems(check: string, list: var): void {
    var next = Object.assign({}, problems)
    next[check] = list
    problems = next
    var k = Object.assign({}, known)
    k[check] = true
    known = k
    reconcileNow()
  }

  function markUnknown(check: string, reason: string): void {
    if (known[check] === false) return
    console.warn("health: " + check + " check unavailable: " + reason)
    var k = Object.assign({}, known)
    k[check] = false
    known = k
  }

  function reconcileNow(): void {
    if (!muteLoaded) return
    if (service && !expectedSeeded) {
      var existing = service.sourceItemKeys()
      expected = existing
      if (!checksStarted) diskLevels = HealthLogic.seedDiskLevels(existing)
      expectedSeeded = true
    }
    if (service) startChecks()
    var open = []
    var knownChecks = []
    for (var check in problems) {
      open = open.concat(problems[check])
      if (known[check] === true) knownChecks.push(check)
    }
    if (!service) {
      // Nothing to post to and nothing the user could have dismissed.
      openProblems = HealthLogic.annotateProblems(open, muted, tools)
      return
    }
    var result = HealthLogic.reconcile(open, knownChecks, expected, service.sourceItemKeys(), muted)
    for (var i = 0; i < result.resolve.length; i++) service.resolveSourceItem(result.resolve[i])
    for (var j = 0; j < result.upsert.length; j++) {
      var p = result.upsert[j]
      service.upsertSourceItem(p.key, HealthLogic.itemFor(p, tools))
    }
    expected = result.expected
    if (JSON.stringify(result.muted) !== JSON.stringify(muted)) {
      muted = result.muted
      muteFile.setText(HealthLogic.serializeMuteFile(muted))
    }
    openProblems = HealthLogic.annotateProblems(open, muted, tools)
  }

  // ---------------------------------------------------- failed units

  function checkUnits(): void {
    if (!systemUnits.running) systemUnits.running = true
    if (!userUnits.running) userUnits.running = true
  }

  function unitResult(scope: string, text: string): void {
    var parsed = HealthLogic.parseFailedUnits(text, scope)
    var parts = Object.assign({}, unitParts)
    parts[scope] = parsed
    unitParts = parts
    if (parts.system === undefined || parts.user === undefined) return
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
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: monitor.unitResult("system", text) }
  }

  Process {
    id: userUnits
    command: ["timeout", "10", "systemctl", "--user", "list-units", "--failed", "--output=json", "--no-pager"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: monitor.unitResult("user", text) }
  }

  // ---------------------------------------------------- disk

  function checkDisk(): void {
    if (!dfProc.running) dfProc.running = true
  }

  Process {
    id: dfProc
    // -l: local filesystems only (a stale network mount cannot hang df, and
    // sshfs/NFS usage is not this machine's disk). timeout: a hang becomes
    // "unknown" instead of freezing the check.
    command: ["timeout", "10", "df", "-l", "--output=source,target,fstype,size,used,avail,pcent", "-B1",
      "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs", "-x", "squashfs", "-x", "overlay"]
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

  function checkReboot(): void {
    if (!release) {
      if (!unameProc.running) unameProc.running = true
      return
    }
    modulesProc.command = ["test", "-d", "/usr/lib/modules/" + release]
    if (!modulesProc.running) modulesProc.running = true
  }

  Process {
    id: unameProc
    command: ["uname", "-r"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        monitor.release = text.trim()
        if (monitor.release) monitor.checkReboot()
        else monitor.markUnknown("reboot", "uname failed")
      }
    }
  }

  Process {
    id: modulesProc
    onExited: function(code) {
      if (code !== 0 && code !== 1) {
        monitor.markUnknown("reboot", "test failed")
        return
      }
      monitor.setProblems("reboot", HealthLogic.rebootProblem(code === 0, monitor.release))
    }
  }

  // ---------------------------------------------------- containers

  function startDocker(): void {
    if (!dockerInfo.running && !dockerPs.running && !dockerEvents.running) dockerInfo.running = true
  }

  Process {
    id: dockerInfo
    command: ["timeout", "10", "docker", "info", "--format", "{{.ServerVersion}}"]
    onExited: function(code) {
      if (code === 0) {
        dockerPs.running = true
      } else {
        monitor.markUnknown("container", "docker not running")
        dockerRetry.restart()
      }
    }
  }

  // On every (re)connect the current container states are the truth: they
  // cover a shell restart (empty history) and events missed while the stream
  // was down. The stream then continues from the snapshot time.
  Process {
    id: dockerPs
    command: ["timeout", "10", "docker", "ps", "-a", "--format", "{{json .}}"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var containers = HealthLogic.parseDockerPs(text)
        if (containers === null) {
          monitor.markUnknown("container", "docker ps failed")
          dockerRetry.restart()
          return
        }
        var now = Date.now()
        monitor.dockerHistory = HealthLogic.seedDockerHistory(monitor.dockerHistory, containers, now)
        dockerEvents.command = ["docker", "events", "--since", String(Math.floor(now / 1000)),
          "--filter", "type=container",
          "--filter", "event=die", "--filter", "event=start", "--filter", "event=destroy",
          "--format", "{{json .}}"]
        dockerEvents.running = true
        monitor.setProblems("container", HealthLogic.containerProblems(monitor.dockerHistory, now))
      }
    }
  }

  Process {
    id: dockerEvents
    stdout: SplitParser {
      onRead: function(line) {
        var event = HealthLogic.parseDockerEvent(line)
        if (!event) return
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

  Timer { id: dockerRetry; interval: 30000; onTriggered: monitor.startDocker() }

  // ---------------------------------------------------- schedule

  Timer {
    interval: 30000; repeat: true; running: true
    onTriggered: {
      monitor.checkUnits()
      // Restart-loop windows drain with time, not only with events.
      if (monitor.known.container === true) {
        var now = Date.now()
        monitor.dockerHistory = HealthLogic.pruneDockerHistory(monitor.dockerHistory, now)
        monitor.setProblems("container", HealthLogic.containerProblems(monitor.dockerHistory, now))
      }
    }
  }
  Timer { interval: 60000; repeat: true; running: true; onTriggered: monitor.checkDisk() }
  Timer { interval: 300000; repeat: true; running: true; onTriggered: monitor.checkReboot() }

  // ---------------------------------------------------- mutes

  FileView {
    id: muteFile
    path: monitor.muteFilePath
    printErrors: false
    atomicWrites: true
    onLoaded: monitor.finishMuteLoad(text())
    // Only a missing file means "no mutes"; any other read error is retried,
    // so a transient failure never brings back dismissed problems.
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) {
        monitor.finishMuteLoad("")
        return
      }
      console.warn("health: cannot read " + monitor.muteFilePath + ": " + FileViewError.toString(error))
      muteRetry.restart()
    }
  }

  Timer { id: muteRetry; interval: 5000; onTriggered: muteFile.reload() }

  function finishMuteLoad(raw: string): void {
    if (muteLoaded) return
    muted = HealthLogic.parseMuteFile(raw)
    muteLoaded = true
    reconcileNow()
  }

  Component.onCompleted: {
    mkdirProc.running = true
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", monitor.stateRoot]
    onExited: {
      muteFile.reload()
      terminalProbe.running = true
    }
  }

  Process {
    id: terminalProbe
    command: ["which", "xdg-terminal-exec"]
    onExited: function(code) {
      monitor.tools = ({ terminal: code === 0 })
      monitor.reconcileNow()
    }
  }
}
