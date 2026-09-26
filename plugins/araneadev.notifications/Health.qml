// System health monitor: failed services, disk almost full, reboot after a
// kernel update, containers exiting. Each open problem is one live inbox item
// (sourceKey) that updates in place and disappears when the problem clears;
// dismissing it mutes the problem until it clears. Rules live in
// HealthLogic.js; this file only runs the checks and applies decisions.

import QtQuick
import Quickshell
import Quickshell.Io
import "HealthLogic.js" as HealthLogic

Item {
  id: health

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

  onServiceChanged: reconcileNow()

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
    if (!muteLoaded || !service) return
    if (!expectedSeeded) {
      // Items already in the inbox (from before a restart) are expected:
      // their absence later means the user removed them.
      expected = service.sourceItemKeys()
      expectedSeeded = true
    }
    var open = []
    var knownChecks = []
    for (var check in problems) {
      open = open.concat(problems[check])
      if (known[check] === true) knownChecks.push(check)
    }
    var result = HealthLogic.reconcile(open, knownChecks, expected, service.sourceItemKeys(), muted)
    for (var i = 0; i < result.resolve.length; i++) service.resolveSourceItem(result.resolve[i])
    for (var j = 0; j < result.upsert.length; j++) {
      var p = result.upsert[j]
      service.upsertSourceItem(p.key, HealthLogic.itemFor(p))
    }
    expected = result.expected
    if (JSON.stringify(result.muted) !== JSON.stringify(muted)) {
      muted = result.muted
      muteFile.setText(HealthLogic.serializeMuteFile(muted))
    }
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
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: health.unitResult("system", text) }
  }

  Process {
    id: userUnits
    command: ["timeout", "10", "systemctl", "--user", "list-units", "--failed", "--output=json", "--no-pager"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: health.unitResult("user", text) }
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
          health.markUnknown("disk", "df failed")
          return
        }
        var result = HealthLogic.diskProblems(rows, health.diskLevels)
        health.diskLevels = result.levels
        health.setProblems("disk", result.problems)
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
        health.release = text.trim()
        if (health.release) health.checkReboot()
        else health.markUnknown("reboot", "uname failed")
      }
    }
  }

  Process {
    id: modulesProc
    onExited: function(code) {
      if (code !== 0 && code !== 1) {
        health.markUnknown("reboot", "test failed")
        return
      }
      health.setProblems("reboot", HealthLogic.rebootProblem(code === 0, health.release))
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
        health.markUnknown("container", "docker not running")
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
          health.markUnknown("container", "docker ps failed")
          dockerRetry.restart()
          return
        }
        var now = Date.now()
        health.dockerHistory = HealthLogic.seedDockerHistory(health.dockerHistory, containers, now)
        dockerEvents.command = ["docker", "events", "--since", String(Math.floor(now / 1000)),
          "--filter", "type=container",
          "--filter", "event=die", "--filter", "event=start", "--filter", "event=destroy",
          "--format", "{{json .}}"]
        dockerEvents.running = true
        health.setProblems("container", HealthLogic.containerProblems(health.dockerHistory, now))
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
        health.dockerHistory = HealthLogic.recordDockerEvent(health.dockerHistory, event, now)
        health.setProblems("container", HealthLogic.containerProblems(health.dockerHistory, now))
      }
    }
    onExited: {
      health.markUnknown("container", "docker events stream ended")
      dockerRetry.restart()
    }
  }

  Timer { id: dockerRetry; interval: 30000; onTriggered: health.startDocker() }

  // ---------------------------------------------------- schedule

  Timer {
    interval: 30000; repeat: true; running: true
    onTriggered: {
      health.checkUnits()
      // Restart-loop windows drain with time, not only with events.
      if (health.known.container === true)
        health.setProblems("container", HealthLogic.containerProblems(health.dockerHistory, Date.now()))
    }
  }
  Timer { interval: 60000; repeat: true; running: true; onTriggered: health.checkDisk() }
  Timer { interval: 300000; repeat: true; running: true; onTriggered: health.checkReboot() }

  // ---------------------------------------------------- mutes

  FileView {
    id: muteFile
    path: health.muteFilePath
    printErrors: false
    atomicWrites: true
    onLoaded: health.finishMuteLoad(text())
    onLoadFailed: health.finishMuteLoad("")
  }

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
    command: ["mkdir", "-p", health.stateRoot]
    onExited: {
      muteFile.reload()
      health.checkUnits()
      health.checkDisk()
      health.checkReboot()
      health.startDocker()
    }
  }
}
