// The notification inbox's snapshot (Inbox.qml), read the way Panel.qml
// reads it, with a real NotificationList consuming the rows: an arrival
// burst, an update of several keys, showPersisted, a reload (clear plus
// append), a remove and a clear each re-evaluate the center rows exactly
// once, the snapshot holds plain copies rather than live model objects, and
// the rows stay sorted and grouped. Before the snapshot, rows held live
// ListModel objects and handing them to the list re-entered the binding;
// the runner fails any test that logs "Binding loop detected".
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.notifications" as Notif
import "plugins/araneadev.notifications/InboxLogic.js" as InboxLogic

ShellRoot {
  id: testRoot

  // Test start in ms; entry timestamps are relative to it.
  readonly property real now: Date.now()

  QmlTest {
    id: t
  }

  Notif.Service {
    id: svc
    windowEnabled: false
    serverEnabled: false
    stateDir: Quickshell.env("HOME") + "/state-snapshot/"
  }

  // Stands in for Panel.qml (which needs a PanelWindow backend): the same
  // rows and criticalCount bindings, feeding a real NotificationList.
  Item {
    id: center

    // Evaluations of rows; a plain object, so counting adds no dependency.
    readonly property var evals: ({
        n: 0
      })
    // Per-app expand overrides, as in Panel.qml.
    property var expanded: ({})
    // Panel.qml's criticalCount binding.
    readonly property int criticalCount: InboxLogic.criticalCount(svc.inbox.snapshot)
    // Panel.qml's rows binding, counting its evaluations.
    readonly property var rows: {
      center.evals.n++
      return InboxLogic.centerRows(svc.inbox.snapshot, center.expanded)
    }

    width: 380
    height: 600

    Notif.NotificationList {
      anchors.fill: parent
      rows: center.rows
      service: svc
    }
  }

  // An entry i ms-seconds old; every fourth one critical, apps rotating.
  function entry(i) {
    return {
      timestamp: testRoot.now - 1000 * (i + 1),
      originalId: i + 1,
      app: ["mail", "chat", "web"][i % 3],
      summary: "summary " + i,
      body: "body " + i,
      urgency: i % 4 === 0 ? 2 : 1
    }
  }

  // Runs FN and returns how often center.rows re-evaluated during it.
  function evaluationsDuring(fn) {
    center.evals.n = 0
    fn()
    return center.evals.n
  }

  Component.onCompleted: {
    t.waitFor(function () {
      return svc.inbox.loadedOnce
    }, 10000, "the inbox loads", function () {
      var counts = []
      for (var i = 0; i < 6; i++)
        counts.push(testRoot.evaluationsDuring(function () {
          svc.inbox.upsert(testRoot.entry(i))
        }))
      t.equal(counts, [1, 1, 1, 1, 1, 1], "each arrival re-evaluates rows once")
      t.equal(center.rows.length, 9, "three groups of two entries each")
      t.equal(center.criticalCount, 2, "critical entries counted from the snapshot")
      t.equal(center.rows[4].entry.summary, "summary 4", "a critical entry sorts before a newer normal one")

      var live = svc.inbox.model.get(0)
      var copy = svc.inbox.snapshot[0]
      t.check(copy !== live && copy.objectName === undefined, "the snapshot holds plain copies, not model objects")
      t.equal(Object.keys(copy).sort(), InboxLogic.ROW_FIELDS.slice().sort(), "a copy carries every row field")

      var before = svc.inbox.snapshot
      t.equal(testRoot.evaluationsDuring(function () {
        svc.inbox.upsert(Object.assign(testRoot.entry(5), {
          summary: "edited",
          body: "edited body",
          urgency: 2
        }))
      }), 1, "an update of several keys re-evaluates rows once")
      t.equal(svc.inbox.get(svc.inbox.snapshot[0].fileName).summary, "edited", "the update reaches the snapshot")
      t.equal(before[0].summary, "summary 5", "an earlier snapshot is left untouched")
      t.equal(center.criticalCount, 3, "the update's urgency counts")

      t.equal(testRoot.evaluationsDuring(function () {
        var e = testRoot.entry(5)
        svc.inbox.showPersisted(e, e, [])
      }), 1, "showPersisted re-evaluates rows once")

      var raw = ""
      for (var j = 0; j < 9; j++)
        raw += JSON.stringify(testRoot.entry(j)) + "\n"
      t.equal(testRoot.evaluationsDuring(function () {
        svc.inbox.finishLoad(raw)
      }), 1, "a reload (clear plus append) re-evaluates rows once")
      t.equal(svc.inbox.snapshot.length, 9, "the reload reaches the snapshot")
      t.equal(center.criticalCount, 3, "critical entries recounted after the reload")

      t.equal(testRoot.evaluationsDuring(function () {
        svc.inbox.remove(svc.inbox.snapshot[0].fileName)
      }), 1, "a remove re-evaluates rows once")
      t.equal(testRoot.evaluationsDuring(function () {
        svc.inbox.clear()
      }), 1, "a clear re-evaluates rows once")
      t.equal(center.rows, [], "a cleared inbox has no rows")
      t.done()
    })
  }
}
