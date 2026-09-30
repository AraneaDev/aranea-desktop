// Behaviour of the menu's guard batch (MenuGuards.qml): one bash run answers
// every `when:` and `checked:`, results replace the previous set, and a second
// request while one runs waits and then runs with the newest items.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: shell

  // How many complete batches reported.
  property int updates: 0

  QmlTest {
    id: t
  }

  Menu.MenuGuards {
    id: guards
    onUpdated: shell.updates += 1
  }

  Component.onCompleted: {
    guards.evaluate({
      shown: {
        id: "shown",
        when: "true"
      },
      hidden: {
        id: "hidden",
        when: "false"
      },
      ticked: {
        id: "ticked",
        checked: "true"
      }
    })
    t.waitFor(function () {
      return shell.updates === 1
    }, 15000, "the first batch reports", function () {
      t.equal(guards.whenResults.shown, true, "a true when: shows")
      t.equal(guards.whenResults.hidden, false, "a false when: hides")
      t.equal(guards.checkedResults.ticked, true, "a true checked: ticks")
      guards.evaluate({
        first: {
          id: "first",
          when: "sleep 0.3"
        }
      })
      guards.evaluate({
        later: {
          id: "later",
          when: "false"
        }
      })
      t.equal(guards.guardsPending, true, "a second request waits for the running batch")
      t.waitFor(function () {
        return shell.updates === 3 && !guards.guardsPending
      }, 15000, "both batches report", function () {
        t.equal(guards.whenResults.later, false, "the waiting request ran with its own items")
        t.equal(guards.whenResults.shown, undefined, "results are replaced, not merged")
        guards.evaluate({})
        t.equal(JSON.stringify(guards.whenResults), "{}", "no guards clears the results at once")
        t.done()
      })
    })
  }
}
