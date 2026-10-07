// Persistent wallpaper process and readback owner; closing search never cancels work.
import QtQuick
import Quickshell.Io
import "../araneadev.shared" as Aranea

Item {
  id: owner
  // Whether search wants fresh catalog and active-wallpaper observations.
  property bool active: false
  // Disable host observations when fixtures provide the process boundary.
  property bool observationsEnabled: true
  // Inert capture mode refuses reads and mutations.
  property bool showcaseActive: false
  // Installed manifest adapter, never a command assembled from search text.
  property string wallpaperPath: Aranea.RuntimePaths.themeRoot + "/scripts/aranea-wallpaper"
  // Maximum confirmation time, including fresh validation and process completion.
  property int confirmationTimeout: 15000
  // Current authoritative catalog, active ID, and schedule context.
  property var wallpaperState: ({
      available: false,
      activeId: null,
      scheduled: false,
      choices: []
    })
  // Read generations reject older asynchronous observations.
  property int readGeneration: 0
  // One snapshot batch at a time prevents slow reads from starving confirmation.
  property bool readInFlight: false
  // Whether an event requested another batch while the current one was running.
  property bool refreshQueued: false
  // Mutation validation callbacks require a fresh follow-up snapshot.
  property var queuedReadCallbacks: []
  // Outstanding mutation identity; independent of active observation leases.
  property string requestId: ""
  // Manifest identity being applied.
  property string targetId: ""
  // Whether the submitted command has exited successfully.
  property bool commandSucceeded: false
  // Whether an external mutation is still physically running after its deadline.
  property bool commandBusy: false
  // Whether a request is validating, applying, or awaiting readback.
  readonly property bool pending: requestId.length > 0
  // Argument-array process boundary shared by reads and the one mutation.
  property var runner: function (argv, done) {
    var process = processFactory.createObject(owner, {
      command: argv,
      completion: done
    })
    process.startRequested = true
    process.running = true
  }
  // Report current-state changes to the search controller.
  signal snapshotChanged
  // Report a request outcome exactly once using its generation identity.
  signal completed(string id, bool succeeded, string message)
  // Tracked processes outlive the menu window and destroy only after completion.
  property Component processFactory: Component {
    Process {
      id: process
      property var completion
      property bool startRequested: false
      property bool startedSuccessfully: false
      property bool finished: false
      function finish(code, stdout, stderr) {
        if (finished)
          return
        finished = true
        completion(code, stdout, stderr)
        process.destroy()
      }
      onStarted: startedSuccessfully = true
      onRunningChanged: if (startRequested && !running && !startedSuccessfully)
        finish(-1, "", "Could not start wallpaper adapter")
      stdout: StdioCollector {
        id: output
      }
      stderr: StdioCollector {
        id: diagnostics
      }
      // Quickshell metadata omits the unused QProcess exit-status enum.
      // qmllint disable signal-handler-parameters
      onExited: function (code) {
        finish(code, output.text, diagnostics.text)
      }
      // qmllint enable signal-handler-parameters
    }
  }

  onWallpaperStateChanged: snapshotChanged()
  onActiveChanged: {
    if (active && observationsEnabled)
      requestRefresh()
    else if (!pending) {
      readGeneration += 1
      refreshTimer.stop()
    }
  }
  // Return the latest validated snapshot; mutation always obtains a new read.
  function snapshot(): var {
    return wallpaperState
  }
  // Run one tracked boundary and turn dispatch exceptions into failed completion.
  function runCommand(argv, done): void {
    try {
      runner(argv, done)
    } catch (error) {
      done(-1, "", "Could not run wallpaper adapter")
    }
  }
  // Coalesce file-watch bursts only while observations or confirmation are needed.
  function requestRefresh(): void {
    if (showcaseActive || !observationsEnabled || (!active && !pending))
      return
    if (!refreshTimer.running)
      refreshTimer.start()
  }
  // Read the catalog and actual owner independently of optimistic selection.
  function refresh(done): bool {
    if (showcaseActive || (pending && !commandSucceeded && !done))
      return false
    if (readInFlight) {
      refreshQueued = true
      if (done)
        queuedReadCallbacks = queuedReadCallbacks.concat([done])
      return true
    }
    readInFlight = true
    var generation = ++readGeneration
    var values = ({})
    var remaining = 3
    var specs = [["choices", [wallpaperPath, "list", "--json"]], ["current", [wallpaperPath, "status", "--json"]], ["schedule", [wallpaperPath, "schedule", "status", "--json"]]]
    specs.forEach(function (spec) {
      owner.runCommand(spec[1], function (code, stdout) {
        var parsed = null
        if (code === 0) {
          try {
            parsed = JSON.parse(stdout)
          } catch (error) {}
        }
        values[spec[0]] = parsed
        remaining -= 1
        if (remaining)
          return
        var followUp = owner.refreshQueued
        var callbacks = owner.queuedReadCallbacks
        owner.readInFlight = false
        owner.refreshQueued = false
        owner.queuedReadCallbacks = []
        if (followUp && (owner.active || owner.pending || callbacks.length)) {
          Qt.callLater(function () {
            owner.refresh(callbacks.length ? function (snapshot) {
              callbacks.forEach(function (callback) {
                callback(snapshot)
              })
            } : null)
          })
        }
        if (generation !== owner.readGeneration)
          return
        var current = values.current
        var choices = Array.isArray(values.choices) ? values.choices : []
        var validCurrent = current && typeof current === "object" && ["available", "unavailable"].indexOf(current.availability) >= 0 && (current.activeId === null || typeof current.activeId === "string")
        owner.wallpaperState = {
          available: Array.isArray(values.choices) && !!validCurrent,
          choices: choices,
          activeId: validCurrent ? current.activeId : null,
          scheduled: !!(values.schedule && values.schedule.enabled === true)
        }
        if (done)
          done(owner.wallpaperState)
        owner.confirmCurrent()
      })
    })
    return true
  }
  // Validate exact installed identity immediately before dispatching the mutation.
  function request(id: string, token: string): bool {
    if (showcaseActive || pending || commandBusy || !id || !token)
      return false
    requestId = token
    targetId = id
    commandSucceeded = false
    deadline.restart()
    refresh(function (snapshot) {
      if (owner.requestId !== token)
        return
      var choice = snapshot.choices.find(function (row) {
        return row && row.id === id && row.available === true
      })
      if (!snapshot.available || !choice) {
        owner.finish(false, "Wallpaper is no longer available")
        return
      }
      if (snapshot.activeId === id) {
        owner.finish(true, "")
        return
      }
      owner.commandBusy = true
      owner.runCommand([owner.wallpaperPath, "set", id], function (code) {
        owner.commandBusy = false
        if (owner.requestId !== token) {
          owner.refresh()
          return
        }
        if (code !== 0) {
          owner.finish(false, "Could not apply wallpaper")
          return
        }
        owner.commandSucceeded = true
        owner.refresh()
      })
    })
    return true
  }
  // Success requires both a successful process and independently observed ID.
  function confirmCurrent(): void {
    if (pending && commandSucceeded && wallpaperState.available && wallpaperState.activeId === targetId)
      finish(true, "")
  }
  // Settle exactly once, retaining late external state as observation only.
  function finish(ok: bool, message: string): void {
    if (!requestId)
      return
    var token = requestId
    requestId = ""
    targetId = ""
    commandSucceeded = false
    deadline.stop()
    completed(token, ok, message)
  }
  Timer {
    id: deadline
    interval: owner.confirmationTimeout
    onTriggered: owner.finish(false, "Timed out applying wallpaper")
  }
  Timer {
    id: refreshTimer
    interval: 100
    onTriggered: owner.refresh()
  }
  // Readback retries remain active after menu close until confirmation settles.
  Timer {
    interval: 250
    repeat: true
    running: owner.pending && owner.commandSucceeded && owner.observationsEnabled
    onTriggered: owner.requestRefresh()
  }
  // Watching the containing directory catches symlink replacement even when
  // the target file content is unchanged. No wallpaper bytes are loaded.
  FileView {
    path: owner.observationsEnabled && owner.active ? Aranea.RuntimePaths.omarchyStateRoot + "/current" : ""
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: owner.requestRefresh()
  }
  FileView {
    path: owner.observationsEnabled && owner.active ? Aranea.RuntimePaths.omarchyStateRoot + "/current/background" : ""
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: owner.requestRefresh()
  }
  FileView {
    path: owner.observationsEnabled && owner.active ? Aranea.RuntimePaths.themeRoot + "/backgrounds/manifest.toml" : ""
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: owner.requestRefresh()
  }
  FileView {
    path: owner.observationsEnabled && owner.active ? Aranea.RuntimePaths.araneaStateRoot + "/wallpaper-schedule" : ""
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: owner.requestRefresh()
  }
}
