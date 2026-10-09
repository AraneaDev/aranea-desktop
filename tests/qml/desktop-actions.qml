// Real action orchestration: DND echo, persistent state and inert captures.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  QmlTest {
    id: t
  }
  QtObject {
    id: notifications
    property bool doNotDisturb: false
    property bool quietHours: true
    property bool echoEnabled: false
    function setDoNotDisturb(value) {
      if (echoEnabled)
        doNotDisturb = value
    }
  }
  Menu.DesktopActionController {
    id: actions
    active: true
    observationsEnabled: false
    notificationOwner: notifications
    audioOwner: null
    dndTimeout: 80
  }
  Component.onCompleted: {
    actions.refreshNow()
    t.equal(actions.records.length, 1, "only available capabilities publish actions")
    t.check(actions.activate("action:dnd"), "DND request accepted")
    t.equal(actions.feedback["action:dnd"].status, "pending", "dispatch alone remains pending")
    t.check(!actions.activate("action:dnd"), "pending DND refuses repeat activation")
    actions.active = false
    notifications.doNotDisturb = true
    t.equal(actions.feedback["action:dnd"].status, "confirmed", "service echo settles after menu close")
    t.check(notifications.quietHours, "DND action preserves quiet hours")
    actions.active = true
    actions.refreshNow()
    t.check(actions.records[0].label.indexOf("Disable") === 0, "reopen projects observed current preference")
    t.check(actions.activate("action:dnd"), "opposite preference can be requested")
    t.step(110, function () {
      t.equal(actions.feedback["action:dnd"].status, "failed", "missing echo times out")
      notifications.echoEnabled = true
      t.check(actions.activate("action:dnd"), "failed action can retry")
      t.equal(actions.feedback["action:dnd"].status, "confirmed", "retry confirms service preference")
      t.check(!notifications.doNotDisturb && notifications.quietHours, "manual preference changes independently of suppression")
      actions.showcaseActive = true
      t.check(!actions.activate("action:dnd"), "inert preview refuses owner mutations")
      t.check(!notifications.doNotDisturb, "preview leaves observed owner unchanged")
      actions.showcaseActive = false
      actions.notificationOwner = null
      actions.refreshNow()
      t.equal(actions.records.length, 0, "missing owner removes only its capability")
      t.check(!actions.activate("action:dnd"), "stale result cannot dispatch without its owner")
      t.equal(actions.beginShowcase({
        dnd: {
          available: true,
          enabled: false,
          quietHours: false
        }
      }, {
        "action:dnd": {
          status: "pending",
          message: ""
        }
      }), "ok", "inert snapshot accepted without live owner")
      t.equal(actions.records[0].key, "action:dnd", "capture publishes fixture identity")
      t.equal(actions.feedback["action:dnd"].status, "pending", "fixture can show pending without submitting work")
      t.check(!actions.activate("action:dnd"), "capture data cannot dispatch an action")
      actions.endShowcase()
      t.equal(actions.records.length, 0, "capture restores actual capability availability")
      t.done()
    })
  }
}
