// Persistent keyboard backlight discovery, commands, queue and read generations.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "DisplaysLogic.js" as DisplaysLogic

Item {
  id: root
  visible: false

  // The keyboard backlight device (DisplaysLogic.kbdDevice), "" for none.
  property string kbdDevice: ""
  // Whether `ls /sys/class/leds` has been read (the device is found once).
  property bool kbdDeviceChecked: false
  // The keyboard light's level and maximum, as read (max 0 hides the row).
  property int kbdValue: 0
  // See kbdValue.
  property int kbdMax: 0
  // A keyboard light level asked for but not yet confirmed, or -1.
  property int kbdPending: -1
  // A level asked for while kbdSetProc was already running, or -1.
  property int kbdQueued: -1
  // Exit and read counters for the keyboard light, as nightSerial.
  property int kbdSerial: 0
  // See kbdSerial.
  property int kbdReadSerial: -1
  // The keyboard light row's control (DisplaysLogic.kbdMode).
  readonly property string kbdMode: DisplaysLogic.kbdMode(kbdMax)

  // ---- Keyboard light ----
  // Reads the keyboard light: finds the device once, then runs
  // `brightnessctl -d <device> -m` when it isn't already running.
  function readKbd() {
    if (!root.kbdDeviceChecked) {
      if (!kbdFindProc.running)
        kbdFindProc.running = true
      return
    }
    if (root.kbdDevice === "" || kbdProc.running)
      return
    kbdProc.command = ["brightnessctl", "-d", root.kbdDevice, "-m"]
    kbdProc.running = true
  }

  // Applies `ls /sys/class/leds`: caches the device and reads it.
  function applyKbdDevice(text) {
    root.kbdDevice = DisplaysLogic.kbdDevice(text)
    root.kbdDeviceChecked = true
    if (root.kbdDevice !== "")
      readKbd()
  }

  // Applies a brightnessctl read, settling requests as applyNight does.
  function applyKbd(text) {
    var state = DisplaysLogic.parseKbdLight(text)
    root.kbdValue = state.current
    root.kbdMax = state.max
    if (root.kbdPending < 0 || kbdSetProc.running || root.kbdQueued >= 0)
      return
    if (root.kbdPending === root.kbdValue || root.kbdReadSerial === root.kbdSerial)
      root.kbdPending = -1
  }

  // The keyboard light level shown: the pending request, else as read.
  function kbdShownLevel() {
    return root.kbdPending >= 0 ? root.kbdPending : root.kbdValue
  }

  // Sets the keyboard light to VALUE (clamped to 0..kbdMax), only while its
  // row shows: shown at once (kbdPending), queued behind a running set, the
  // last one winning.
  function setKbd(value) {
    if (root.kbdDevice === "" || root.kbdMax <= 0)
      return
    var level = Math.max(0, Math.min(root.kbdMax, Math.round(Number(value) || 0)))
    if (level === kbdShownLevel())
      return
    root.kbdPending = level
    if (kbdSetProc.running) {
      root.kbdQueued = level
      return
    }
    runKbdCommand(level)
  }

  // Starts the keyboard light command for LEVEL (DisplaysLogic.kbdCommand).
  function runKbdCommand(level) {
    kbdSetProc.command = DisplaysLogic.kbdCommand(root.kbdDevice, level, root.kbdMax)
    kbdSetProc.running = true
  }

  // kbdSetProc exited with EXITCODE: runs the queued level, else a failure
  // drops the request, and the level is re-read either way.
  function kbdExited(exitCode) {
    root.kbdSerial++
    if (root.kbdQueued >= 0) {
      var level = root.kbdQueued
      root.kbdQueued = -1
      runKbdCommand(level)
      return
    }
    if (exitCode !== 0)
      root.kbdPending = -1
    readKbd()
  }

  // qmllint disable signal-handler-parameters
  // The keyboard light setter (runKbdCommand sets the command).
  Process {
    id: kbdSetProc
    onExited: function (exitCode) {
      root.kbdExited(exitCode)
    }
  }
  // qmllint enable signal-handler-parameters

  // `ls /sys/class/leds`, once, for the keyboard backlight device.
  Process {
    id: kbdFindProc
    command: ["ls", "/sys/class/leds"]
    stdout: StdioCollector {
      id: kbdFindOut
      waitForEnd: true
      onStreamFinished: root.applyKbdDevice(kbdFindOut.text)
    }
  }

  // The keyboard light read (readKbd sets the command); records which set
  // exit it started after, as stateProc does.
  Process {
    id: kbdProc
    onRunningChanged: {
      if (kbdProc.running)
        root.kbdReadSerial = root.kbdSerial
      else if (root.kbdPending >= 0 && !kbdSetProc.running && root.kbdReadSerial !== root.kbdSerial)
        Qt.callLater(root.readKbd)
    }
    stdout: StdioCollector {
      id: kbdOut
      waitForEnd: true
      onStreamFinished: root.applyKbd(kbdOut.text)
    }
  }
}
