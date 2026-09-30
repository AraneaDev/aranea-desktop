// Guard evaluation for the Aranea menu (MenuGuards): `when:` (visibility) and
// `checked:` (check mark) are bash expressions, batched into one bash process
// per (re)load so opening the menu never waits on them. Menu.qml owns one.
import Quickshell.Io
import QtQuick
import "MenuModel.js" as MenuModel

Item {
  id: guards

  // Latest `when:` results by id (false hides the item).
  property var whenResults: ({})
  // Latest `checked:` results by id (true adds the check mark).
  property var checkedResults: ({})
  // Set when an evaluation was requested while one was running; it reruns afterwards.
  property bool guardsPending: false
  // Items of the newest request; a deferred rerun uses these.
  property var requestedItems: ({})

  // Emitted when a complete batch has replaced the results.
  signal updated

  // Runs every guard in ITEMS in one bash batch (deferred if one is in flight).
  function evaluate(items: var): void {
    guards.requestedItems = items || ({})
    // Process ignores a command change while it is running, and `collected`
    // belongs to the run in flight, so a second evaluation cannot overwrite
    // the first: it would throw away the lines already read and never start.
    // The surviving tail then lands as the whole answer, and every id lost
    // with it goes back to showing, since a `when:` only hides on an explicit
    // false. Wait for the run in flight and evaluate once it lands instead.
    if (guardProc.running) {
      guards.guardsPending = true
      return
    }
    guards.guardsPending = false

    var script = MenuModel.guardScript(guards.requestedItems)
    if (!script) {
      guards.whenResults = ({})
      guards.checkedResults = ({})
      return
    }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function (data) {
        guardProc.collected += data + "\n"
      }
    }
    onExited: function (exitCode, exitStatus) {
      // A batch that was killed rather than finished has only told us about
      // the rows it reached, and a row whose `when:` went unanswered shows.
      // Keep the last complete set rather than let a half-read one through.
      // A signal leaves the exit code at 0, so the status is what tells us.
      if (exitCode !== 0 || exitStatus !== 0) {
        if (guards.guardsPending)
          Qt.callLater(function () {
            guards.evaluate(guards.requestedItems)
          })
        return
      }

      var nextWhen = ({})
      var nextChecked = ({})
      var lines = guardProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line)
          continue
        var colon = line.lastIndexOf(":")
        if (colon < 0)
          continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0)
          continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w")
          nextWhen[id] = value
        else if (tag === "c")
          nextChecked[id] = value
      }
      guards.whenResults = nextWhen
      guards.checkedResults = nextChecked
      guards.updated()
      // Run the evaluation that had to stand aside. Deferred by a turn so the
      // process is settled before its command is set again.
      if (guards.guardsPending)
        Qt.callLater(function () {
          guards.evaluate(guards.requestedItems)
        })
    }
  }
}
