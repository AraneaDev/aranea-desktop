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

  // Reads the second service's settings file.
  FileView {
    id: settingsReader
    blockLoading: true
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

    t.step(800, function () {
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

      // DND on, then the service goes before its debounced save fires.
      var second = serviceComponent.createObject(testRoot)
      t.step(800, function () {
        t.check(second.settingsLoaded, "second service loaded its settings")
        second.setDoNotDisturb(true)
        second.destroy()
        t.step(300, function () {
          settingsReader.path = testRoot.stateRoot + "b/notifications.json"
          var saved = {}
          try {
            saved = JSON.parse(settingsReader.text())
          } catch (e) {
            saved = {}
          }
          t.equal(saved.dnd, true, "DND written when the service goes away")
          t.done()
        })
      })
    })
  }
}
