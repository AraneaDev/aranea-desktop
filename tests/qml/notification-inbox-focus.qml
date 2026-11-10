// Real inbox delivery, replacement, activation and fresh restore with native IO adapted.
import QtQuick
import Quickshell
import "lib"
import "fixtures/notification-hyprland"
import "plugins/araneadev.notifications" as Notif

ShellRoot {
  id: host
  QmlTest {
    id: t
  }
  QtObject {
    id: senderSignals
    signal closed
    signal hintsChanged
  }
  Notif.Service {
    id: svc
    windowEnabled: false
    serverEnabled: false
    stateDir: Quickshell.env("HOME") + "/inbox-focus/"
  }
  Component {
    id: restoredComponent
    Notif.Service {
      windowEnabled: false
      serverEnabled: false
      stateDir: svc.stateDir
    }
  }

  // Supply native window records only; production resolution/dispatch stays real.
  function windows() {
    Hyprland.toplevels = {
      values: [
        {
          lastIpcObject: {
            class: "org.telegram.desktop",
            address: "0x101",
            pid: 101
          }
        },
        {
          lastIpcObject: {
            class: "org.telegram.desktop",
            address: "0x202",
            pid: 202
          }
        },
        {
          lastIpcObject: {
            class: "editor",
            address: "0x303",
            pid: 303
          }
        }
      ]
    }
  }

  // Deliver an ordinary retained notification through the real service and Inbox.
  function deliver(id, app, pid) {
    var ref = {
      id: id,
      appName: app,
      urgency: 1,
      hints: {
        "sender-pid": pid
      },
      tracked: false,
      actions: [],
      closed: senderSignals.closed,
      hintsChanged: senderSignals.hintsChanged,
      dismiss: function () {
        this.tracked = false
        senderSignals.closed()
      }
    }
    svc.handleNotification(ref)
    return {
      ref: ref,
      key: svc.inbox.snapshot[0].fileName
    }
  }

  Component.onCompleted: t.waitFor(function () {
    return svc.inbox.loadedOnce
  }, 5000, "inbox loads", function () {
    windows()
    var delivery = deliver(101, "Telegram Desktop", 101)
    t.equal(svc.inbox.count, 1, "ordinary delivery enters actual retained inbox")
    t.equal(svc.inbox.get(delivery.key).senderPid, undefined, "inbox presentation schema excludes live PID metadata")
    svc.invokeInbox(delivery.key)
    t.equal(Hyprland.dispatched, ['hl.dsp.focus({window = hl.get_window("address:0x101")})'], "live inbox PID selects sender among ambiguous same-class windows")
    t.check(!delivery.ref.tracked && svc.inbox.count === 0, "activation consumes only its own live inbox sender")

    delivery = deliver(102, "Editor", 101)
    svc.invokeInbox(delivery.key)
    t.equal(Hyprland.dispatched[1], 'hl.dsp.focus({window = hl.get_window("address:0x101")})', "live inbox PID beats unique conflicting display class")

    var before = Hyprland.dispatched.length
    delivery = deliver(103, "Telegram Desktop", 101)
    delivery.ref.tracked = false
    senderSignals.closed()
    t.check(!svc.inboxRefs[delivery.key] && !svc.liveSnapshots[delivery.key], "sender close removes retained live metadata")
    svc.invokeInbox(delivery.key)
    t.equal(Hyprland.dispatched.length, before, "closed inbox sender cannot revive PID focus claim")

    delivery = deliver(104, "Telegram Desktop", 101)
    delivery.ref.tracked = false
    svc.invokeInbox(delivery.key)
    t.equal(Hyprland.dispatched.length, before, "untracked sender cannot focus from retained metadata before close signal")

    delivery = deliver(105, "Telegram Desktop", 101)
    delivery.ref.hints = {
      "sender-pid": 202
    }
    senderSignals.hintsChanged()
    svc.invokeInbox(delivery.key)
    t.equal(Hyprland.dispatched[before], 'hl.dsp.focus({window = hl.get_window("address:0x202")})', "live inbox replacement uses the current sender claim")

    var original = deliver(106, "Telegram Desktop", 101)
    // Wait behind actual writes, then create a fresh Service with no live maps.
    svc.inbox.enqueue(["true"], function () {
      var restored = restoredComponent.createObject(host)
      t.waitFor(function () {
        return restored.inbox.loadedOnce
      }, 5000, "fresh service restores inbox", function () {
        t.check(original.ref.tracked && !!svc.inboxRefs[original.key], "original sender remains live during fresh restore")
        t.equal(restored.inbox.count, 1, "fresh service restores the persisted notification")
        t.equal(Object.keys(restored.liveSnapshots).length, 0, "fresh restore has no retained sender snapshot")
        var count = Hyprland.dispatched.length
        restored.invokeInbox(original.key)
        t.equal(Hyprland.dispatched.length, count, "fresh restore cannot revive a PID claim even while original sender exists")
        svc.clearInbox()
        restored.destroy()
        t.done()
      })
    })
  })
}
