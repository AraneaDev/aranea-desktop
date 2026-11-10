// Behaviour of the notification service (Service.qml) with no toast windows
// and no notification server, its state under the sandbox HOME: a toast held
// on two screens stays paused until both copies let go, a clear while the
// inbox loads keeps it empty, pruning an old entry dismisses it at its
// sender, and a DND toggle survives the service going away at once.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "plugins/araneadev.notifications" as Notif
import "plugins/araneadev.notifications/NotificationLogic.js" as Logic

ShellRoot {
  // Not `shell`: the service has a `shell` property that would shadow it.
  id: testRoot

  // Test start in ms; entry timestamps are relative to it.
  readonly property real now: Date.now()
  // State root for the services under test.
  readonly property string stateRoot: Quickshell.env("HOME") + "/state-"

  QmlTest {
    id: t
  }

  Notif.Service {
    id: svc
    windowEnabled: false
    serverEnabled: false
    stateDir: testRoot.stateRoot + "a/"
  }

  // A second service, created and destroyed by the DND check.
  Component {
    id: serviceComponent
    Notif.Service {
      windowEnabled: false
      serverEnabled: false
      stateDir: testRoot.stateRoot + "b/"
    }
  }

  // Stands in for a sender's live Notification object.
  QtObject {
    id: fakeRef
    property bool tracked: true
    property int dismissed: 0

    // Records a dismiss at the sender.
    function dismiss() {
      dismissed += 1
    }
  }

  property var invokedActions: []
  QtObject {
    id: actionRef
    property bool tracked: true
    property var actions: [
      {
        identifier: "default",
        text: "Default",
        invoke: function () {
          invokedActions.push("default")
        }
      },
      {
        identifier: "open",
        text: "Open",
        invoke: function () {
          invokedActions.push("open")
        }
      },
      {
        identifier: "cut",
        text: "Omacut",
        invoke: function () {
          invokedActions.push("cut")
        }
      }
    ]
    function dismiss() {
      tracked = false
    }
  }

  QtObject {
    id: senderSignals
    signal closed
    signal hintsChanged
    signal actionsChanged
  }

  // Only the native Notification boundary is replaced: production delivery,
  // watchers, replacement and sender-close handling all run unchanged.
  function checkActionLifetime(then) {
    var first = {
      id: 41,
      appName: "omarchy-action",
      urgency: 0,
      tracked: false,
      hints: {
        "omarchy-actions": '[{"label":"Open","argv":["/usr/bin/false"]}]'
      },
      actions: [
        {
          identifier: "old",
          text: "Old",
          invoke: function () {
            invokedActions.push("old")
          }
        }
      ],
      closed: senderSignals.closed,
      hintsChanged: senderSignals.hintsChanged,
      actionsChanged: senderSignals.actionsChanged,
      dismiss: function () {
        this.tracked = false
        senderSignals.closed()
      }
    }
    svc.handleNotification(first)
    t.step(20, function () {
      t.check(first.tracked, "delivery keeps sender alive for actions")
      t.equal(svc.actionsFor(41).map(function (a) {
        return a.label
      }), ["Open", "Old"], "hint buttons precede sender buttons")
      var revision = svc.actionsRevision
      first.hints = {
        "omarchy-actions": '[{"label":"Omacut","argv":["/usr/bin/false"]}]'
      }
      senderSignals.hintsChanged()
      t.equal(svc.actionsFor(41).map(function (a) {
        return a.label
      }), ["Omacut", "Old"], "replacement refreshes action hints in the same popup")
      t.equal(svc.popupModel.count, 1, "replacement never duplicates the popup")
      t.check(svc.actionsRevision > revision, "replacement invalidates rendered action choices")
      first.actions = [
        {
          identifier: "new",
          text: "New",
          invoke: function () {
            invokedActions.push("new")
          }
        }
      ]
      senderSignals.actionsChanged()
      t.equal(svc.actionsFor(41).map(function (a) {
        return a.label
      }), ["Omacut", "New"], "sender action updates are observed")
      first.tracked = false
      senderSignals.closed()
      t.equal(svc.actionsFor(41).map(function (a) {
        return a.label
      }), ["Omacut"], "sender close removes only live libnotify buttons")
      t.equal(svc.invokePopupAction(41, 1), false, "closed sender choice cannot run")
      t.equal(invokedActions, [], "replacement and close never invoke stale actions")
      svc.clearPopups()
      first.hints = {}
      first.actions = [
        {
          identifier: "close",
          text: "Close",
          invoke: function () {
            first.tracked = false
            senderSignals.closed()
          }
        }
      ]
      svc.handleNotification(first)
      t.step(20, function () {
        t.equal(svc.invokePopupAction(41, 0), true, "a sender may close synchronously while its action runs")
        t.equal(svc.popupModel.count, 0, "a synchronously closed sender still consumes its own card")
        svc.clearPopups()
        then()
      })
    })
  }

  FileView {
    id: actionReader
    blockLoading: true
    path: testRoot.stateRoot + "actions.json"
  }

  function checkActions(then) {
    var row = Logic.snapshotOf({
      id: 31,
      appName: "omarchy-action"
    }, testRoot.now)
    svc.popupModel.append(row)
    svc.liveRefs = ({
        31: actionRef
      })
    t.equal(svc.actionsFor(31).map(function (a) {
      return a.label
    }), ["Open", "Omacut"], "default click is separate from sender buttons")
    // Another card took visual slot zero after the first card was rendered.
    svc.popupModel.insert(0, Logic.snapshotOf({
      id: 32
    }, testRoot.now + 1))
    t.equal(svc.invokePopupAction(31, 1), true, "action targets stable original identity after insertion")
    t.equal(invokedActions, ["cut"], "selected live sender action invoked exactly once")
    t.equal(svc.popupModel.get(0).originalId, 32, "newer card was not invoked or removed")
    t.equal(svc.invokePopupAction(31, 0), false, "removed card cannot fall through to its neighbour")
    svc.clearPopups()
    svc.liveRefs = ({})
    svc.popupModel.append(row)
    t.equal(svc.actionsFor(31), [], "restored entries never revive sender actions")
    t.equal(svc.invokePopupAction(31, 0), false, "a dead sender action cannot run")
    svc.clearPopups()

    // Exercise real Util.execArgv at the process boundary, recording literals.
    var argv = ["/usr/bin/python3", "-c", "import json,sys;json.dump(sys.argv[2:],open(sys.argv[1], 'w'))", actionReader.path, "/tmp/a b.mp4", "a\"b", "$(touch nope)", "a;b"]
    var hint = JSON.stringify([
      {
        label: "Open",
        argv: ["/usr/bin/false"]
      },
      {
        label: "Omacut",
        argv: argv
      }
    ])
    var execRow = Logic.snapshotOf({
      id: 33,
      hints: {
        "omarchy-actions": hint
      }
    }, testRoot.now)
    svc.popupModel.append(execRow)
    t.equal(svc.actionsFor(33).map(function (a) {
      return a.label
    }), ["Open", "Omacut"], "argv buttons preserve visible order")
    t.equal(svc.invokePopupAction(33, -1), false, "negative choice refused")
    t.equal(svc.invokePopupAction(33, 2), false, "out-of-range choice refused")
    t.equal(svc.invokePopupAction(33, 1), true, "selected argv action launches")
    t.equal(svc.invokePopupAction(33, 1), false, "consumed action cannot launch twice")
    t.waitFor(function () {
      actionReader.reload()
      return actionReader.text().length > 0
    }, 5000, "argv action recorder finishes", function () {
      t.equal(JSON.parse(actionReader.text()), ["/tmp/a b.mp4", "a\"b", "$(touch nope)", "a;b"], "argv metacharacters survive process execution literally")
      then()
    })
  }

  // Reads the second service's settings file.
  FileView {
    id: settingsReader
    blockLoading: true
  }

  // The second service's settings file, parsed; {} while missing or torn.
  function savedSettings() {
    try {
      return JSON.parse(settingsReader.text())
    } catch (e) {
      return {}
    }
  }

  Component.onCompleted: {
    // A toast hovered on two screens: paused until both copies let go.
    svc.holdPopup("1-1", true)
    svc.holdPopup("1-1", true)
    t.check(svc.popupHeld("1-1"), "hovered toast is paused")
    svc.holdPopup("1-1", false)
    t.check(svc.popupHeld("1-1"), "still paused while the other screen holds it")
    svc.holdPopup("1-1", false)
    t.check(!svc.popupHeld("1-1"), "released on both screens")

    // Clear before the inbox has loaded: the loaded entries stay gone.
    t.check(!svc.inbox.loadedOnce, "inbox still loading")
    svc.inbox.clear()
    svc.inbox.finishLoad(JSON.stringify({
      timestamp: testRoot.now - 1000,
      originalId: 7,
      app: "mail",
      summary: "loaded late"
    }) + "\n")
    t.equal(svc.inbox.count, 0, "a clear during load wins over the loaded entries")

    t.waitFor(function () {
      return svc.inbox.loadedOnce && svc.settingsLoaded
    }, 10000, "the first service loads", function () {
      // An entry older than a week is pruned and dismissed at its sender.
      var old = {
        timestamp: testRoot.now - 8 * 24 * 3600 * 1000,
        originalId: 9,
        app: "chat",
        summary: "stale"
      }
      var refs = {}
      refs["" + old.timestamp + "-9.json"] = fakeRef
      svc.inboxRefs = refs
      svc.inbox.upsert(old)
      t.equal(svc.inbox.count, 0, "old entry pruned")
      t.equal(fakeRef.dismissed, 1, "pruning dismisses the entry at its sender")

      checkActionLifetime(function () {
        checkActions(function () {
          // DND on, then the service goes before its debounced save fires.
          var second = serviceComponent.createObject(testRoot)
          t.waitFor(function () {
            return second.settingsLoaded
          }, 10000, "the second service loads its settings", function () {
            t.check(second.settingsLoaded, "second service loaded its settings")
            second.setDoNotDisturb(true)
            second.destroy()
            settingsReader.path = testRoot.stateRoot + "b/notifications.json"
            t.waitFor(function () {
              settingsReader.reload()
              return testRoot.savedSettings().dnd !== undefined
            }, 5000, "the settings file is written", function () {
              t.equal(testRoot.savedSettings().dnd, true, "DND written when the service goes away")
              t.done()
            })
          })
        })
      })
    })
  }
}
