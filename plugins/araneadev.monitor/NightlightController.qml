// Persistent night-light commands and read generations; visibility stays in Panel.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "DisplaysLogic.js" as DisplaysLogic

Item {
  id: root
  visible: false

  // Whether `omarchy-toggle-nightlight --status` answered (the row hides
  // otherwise).
  property bool nightAvailable: false
  // Whether the night light is on, as read.
  property bool nightOn: false
  // The night light row's caption (DisplaysLogic.nightlightCaption).
  property string nightCaption: "Off"
  // The night light temperature as read (K), or null with none; the
  // toggle's prediction depends on it (DisplaysLogic.nightToggleTarget).
  property var nightTemperature: null
  // The night light state asked for but not yet confirmed by a re-read, or
  // null for none. Shown at once and pulsing busy.
  property var nightPending: null
  // The state the running omarchy-toggle-nightlight will leave, so its exit
  // handler can toggle again when the latest request differs (last wins).
  property bool nightTarget: false
  // How many night light toggles have exited, and the count when the
  // running status read started: a read only settles a request when it
  // started after the last toggle exited.
  property int nightSerial: 0
  // See nightSerial.
  property int nightReadSerial: -1

  // ---- Night light ----
  // Reads `omarchy-toggle-nightlight --status` when it isn't already running.
  function readNight() {
    if (!nightProc.running)
      nightProc.running = true
  }

  // Applies a status read: shows it, settles a request it confirms, and
  // drops any request once the read started after the last toggle exited.
  function applyNight(text) {
    var state = DisplaysLogic.parseNightlight(text)
    root.nightAvailable = state.available
    root.nightOn = state.enabled
    root.nightTemperature = state.temperature
    root.nightCaption = DisplaysLogic.nightlightCaption(state)
    if (typeof root.nightPending !== "boolean" || nightToggleProc.running)
      return
    if (root.nightPending === root.nightOn || root.nightReadSerial === root.nightSerial)
      root.nightPending = null
  }

  // Flips the night light, only while its row shows: the state the toggle
  // will leave is shown at once (nightPending, pulsing busy). From a read
  // that is the script's own rule (DisplaysLogic.nightToggleTarget: an odd
  // temperature ends off); from a pending request, its opposite. A flip
  // while the toggle runs only changes what is asked for; the exit handler
  // toggles again if it still differs (the last one wins).
  function toggleNightlight() {
    var target = typeof root.nightPending === "boolean" ? !root.nightPending : DisplaysLogic.nightToggleTarget({
      temperature: root.nightTemperature
    })
    root.nightPending = target
    if (nightToggleProc.running)
      return
    runNightToggle(target)
  }

  // Starts omarchy-toggle-nightlight, which will leave the light at TARGET.
  function runNightToggle(target) {
    root.nightTarget = target
    nightToggleProc.running = true
  }

  // nightToggleProc exited with EXITCODE: toggles again when the latest
  // request differs from what this toggle left; else a failure drops the
  // request, and the status is re-read either way.
  function nightExited(exitCode) {
    root.nightSerial++
    if (exitCode === 0 && typeof root.nightPending === "boolean" && root.nightPending !== root.nightTarget) {
      runNightToggle(root.nightPending)
      return
    }
    if (exitCode !== 0)
      root.nightPending = null
    readNight()
  }

  // qmllint disable signal-handler-parameters
  // omarchy-toggle-nightlight (no arguments: it flips the light).
  Process {
    id: nightToggleProc
    command: ["omarchy-toggle-nightlight"]
    onExited: function (exitCode) {
      root.nightExited(exitCode)
    }
  }

  // qmllint enable signal-handler-parameters

  // The night light status read; records which toggle exit it started
  // after, as stateProc does.
  Process {
    id: nightProc
    command: ["omarchy-toggle-nightlight", "--status"]
    onRunningChanged: {
      if (nightProc.running)
        root.nightReadSerial = root.nightSerial
      else if (typeof root.nightPending === "boolean" && !nightToggleProc.running && root.nightReadSerial !== root.nightSerial)
        Qt.callLater(root.readNight)
    }
    stdout: StdioCollector {
      id: nightOut
      waitForEnd: true
      onStreamFinished: root.applyNight(nightOut.text)
    }
  }
}
