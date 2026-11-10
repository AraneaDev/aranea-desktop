// Restored inbox buttons use production parsing, list rendering and execution.
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "lib"
import "plugins/araneadev.notifications" as Notif
import "plugins/araneadev.notifications/InboxLogic.js" as InboxLogic

ShellRoot {
  id: root
  // Actions emitted by the real list during this fixture.
  property var events: []
  // Native sender action count, separate from persisted argv actions.
  property int senderInvoked: 0
  QtObject {
    id: senderSignals
    signal closed
    signal actionsChanged
  }
  // Stable epoch for the persisted inbox fixture identity.
  readonly property real now: Date.now()
  // Persisted entry name passed to the real inbox service.
  readonly property string fileName: String(now - 100) + "-71.json"
  QmlTest {
    id: t
  }
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }
  Notif.Service {
    id: svc
    windowEnabled: false
    serverEnabled: false
    stateDir: Quickshell.env("HOME") + "/inbox-actions/"
  }
  FileView {
    id: recorder
    path: Quickshell.env("HOME") + "/inbox-actions.json"
    blockLoading: true
  }
  FloatingWindow {
    implicitWidth: 440
    implicitHeight: 500
    visible: true
    Notif.NotificationList {
      id: list
      width: 400
      height: 480
      service: svc
      rows: InboxLogic.centerRows(svc.inbox.snapshot, {})
      onAction: function (name, arg) {
        events.push([name, arg])
        if (name === "invokeAction") {
          var row = list.rows[arg.index]
          if (row && InboxLogic.rowKey(row) === arg.key)
            svc.invokeInboxAction(row.entry.fileName, arg.actionIndex)
        }
      }
    }
  }
  // Exercise current sender actions after the persisted-entry checks.
  function checkLiveInbox() {
    var ref = {
      id: 72,
      appName: "Video",
      urgency: 1,
      tracked: false,
      closed: senderSignals.closed,
      actionsChanged: senderSignals.actionsChanged,
      hints: {
        "omarchy-actions": '[{"label":"Open","argv":["/usr/bin/false"]}]'
      },
      actions: [
        {
          identifier: "default",
          text: "Default",
          invoke: function () {
            senderInvoked += 100
          }
        },
        {
          identifier: "native",
          text: "Native",
          invoke: function () {
            senderInvoked += 1
          }
        }
      ],
      dismiss: function () {
        this.tracked = false
        senderSignals.closed()
      }
    }
    svc.handleNotification(ref)
    var key = svc.inbox.snapshot[0].fileName
    t.check(ref.tracked, "retained inbox keeps its native sender tracked")
    t.equal(svc.inboxActionsFor(key).map(function (a) {
      return a.label
    }), ["Open", "Native"], "retained inbox offers argv and live native actions separately from default")
    ref.actions = [
      {
        identifier: "native",
        text: "Updated",
        invoke: function () {
          senderInvoked += 1
        }
      }
    ]
    var revision = svc.actionsRevision
    senderSignals.actionsChanged()
    t.check(svc.actionsRevision > revision, "native inbox action replacement invalidates rendered buttons")
    t.equal(svc.inboxActionsFor(key).map(function (a) {
      return a.label
    }), ["Open", "Updated"], "native inbox action replacement is observed")
    t.equal(svc.invokeInboxAction(key, 1), true, "selected live inbox sender action invokes")
    t.equal(senderInvoked, 1, "native inbox choice runs once without its default click")
    t.check(!ref.tracked, "consuming inbox entry releases its sender")
    t.equal(svc.inbox.count, 0, "consumed live inbox entry disappears")
    ref.id = 73
    svc.handleNotification(ref)
    key = svc.inbox.snapshot[0].fileName
    ref.tracked = false
    senderSignals.closed()
    t.equal(svc.inboxActionsFor(key).map(function (a) {
      return a.label
    }), ["Open"], "sender close leaves persistent argv but removes native inbox actions")
    t.equal(svc.invokeInboxAction(key, 1), false, "closed native inbox choice never revives")
    svc.clearInbox()
  }

  // Find the real action controls belonging to an inbox row.
  function buttons() {
    return t.findChildren(list, "notificationActionButton")
  }
  Component.onCompleted: t.waitFor(function () {
    return svc.inbox.loadedOnce
  }, 5000, "inbox loaded", function () {
    checkLiveInbox()
    var command = ["/usr/bin/python3", "-c", "import json,sys;json.dump(sys.argv[2:],open(sys.argv[1], 'w'))", recorder.path]
    // finishLoad receives the exact format written by the inbox persistence.
    svc.inbox.finishLoad(JSON.stringify({
      timestamp: now - 100,
      originalId: 71,
      app: "Video",
      summary: "Restored",
      execActions: JSON.stringify([
        {
          label: "Open",
          argv: command.concat(["wrong"])
        },
        {
          label: "Omacut",
          argv: command.concat(["/tmp/a b.mp4", 'a"b', "$(touch nope)", "a;b"])
        }
      ])
    }) + "\n")
    t.equal(svc.inboxActionsFor(fileName).map(function (a) {
      return a.label
    }), ["Open", "Omacut"], "restored inbox retains runnable argv choices")
    t.equal(svc.inboxActionsFor("missing.json"), [], "missing inbox identity offers no actions")
    t.equal(svc.invokeInboxAction("missing.json", 0), false, "missing inbox identity cannot fall through")
    t.equal(svc.invokeInboxAction(fileName, 2), false, "out-of-range inbox choice is refused")
    t.step(350, function () {
      t.equal(buttons().map(function (b) {
        return b.label
      }), ["Open", "Omacut"], "restored card actually renders both buttons")
      var point = buttons()[0].mapToItem(list, buttons()[0].width / 2, buttons()[0].height / 2)
      pointer.mousePress(list, point.x, point.y)
      var replacement = Object.assign({}, svc.inbox.get(fileName))
      replacement.summary = "Replaced while pressed"
      svc.inbox.upsert(replacement)
      pointer.mouseRelease(list, point.x, point.y)
      t.equal(events.filter(function (e) {
        return e[0] !== "hover"
      }), [], "inbox replacement refuses an old button press")
      t.step(350, function () {
        pointer.mouseClick(buttons()[1])
        t.equal(events.filter(function (e) {
          return e[0] !== "hover"
        }), [["invokeAction",
            {
              index: 1,
              key: "e:" + fileName,
              actionIndex: 1
            }
          ]], "the selected inbox button emits exactly one keyed event")
        t.equal(svc.inbox.count, 0, "invoked inbox entry is consumed")
        t.equal(svc.invokeInboxAction(fileName, 1), false, "removed inbox entry cannot invoke twice")
        t.waitFor(function () {
          recorder.reload()
          return recorder.text().length > 0
        }, 5000, "inbox action executes", function () {
          t.equal(JSON.parse(recorder.text()), ["/tmp/a b.mp4", 'a"b', "$(touch nope)", "a;b"], "restored selected argv executes literally")
          t.done()
        })
      })
    })
  })
}
