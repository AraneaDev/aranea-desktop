// Quick actions in the real menu: fresh identity, outcome feedback and close policy.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu
import "plugins/araneadev.audio" as Audio

ShellRoot {
  id: host
  // Audio dispatches intercepted below the real default-selection owner.
  property var dispatched: []
  // Device fixtures with complete default-selection identity.
  property var speakers: ({
      id: 7,
      name: "speaker",
      description: "Studio Speakers",
      isSink: true,
      isStream: false,
      audio: ({})
    })
  // Current output, distinct from the first selectable target.
  property var headphones: ({
      id: 8,
      name: "headphones",
      description: "Headphones",
      isSink: true,
      isStream: false,
      audio: ({})
    })
  QmlTest {
    id: t
  }
  QtObject {
    id: notifications
    property bool doNotDisturb: false
    property bool quietHours: true
    function setDoNotDisturb(value) {
      doNotDisturb = value
    }
  }
  QtObject {
    id: backend
    property var nodes: ({
        values: [host.speakers, host.headphones]
      })
    property var defaultAudioSink: host.headphones
    property var defaultAudioSource: null
  }
  Audio.AudioDefaults {
    id: defaults
    backend: backend
    observationsEnabled: false
    confirmationTimeout: 100
    sinkAvailabilityLoaded: true
    sinkAvailability: ({
        speaker: true,
        headphones: true
      })
    sendDefault: function (channel, node) {
      host.dispatched = host.dispatched.concat([[channel, node.id, node.name]])
    }
  }
  Menu.Menu {
    id: menu
    windowEnabled: false
    defaultMenuPath: Qt.resolvedUrl("fixtures/omarchy-menu.jsonc").toString().replace("file://", "")
    run: function (command) {
      t.check(false, "quick action cannot use legacy command runner")
    }
  }
  FloatingWindow {
    implicitWidth: 520
    implicitHeight: 650
    visible: true
    Menu.MenuSurface {
      id: surface
      width: menu.cardWidth
      height: menu.cardHeight
      root: menu
    }
  }
  // Deliver an event through the production key map.
  function key(code) {
    return {
      key: code,
      modifiers: Qt.NoModifier,
      text: "",
      accepted: false
    }
  }
  // Find an exact canonical action independent of its current rank.
  function find(identity) {
    for (var i = 0; i < menu.displayModel.count; i++)
      if (menu.displayModel.get(i).desktopKey === identity)
        return i
    return -1
  }
  Component.onCompleted: {
    menu.desktopActions.notificationOwner = notifications
    menu.desktopActions.audioOwner = defaults
    menu.desktopSearch.compositor = null
    menu.desktopSearch.fixtureWindows = []
    menu.desktopSearch.fixtureWorkspaces = []
    menu.desktopActions.wallpaper.runner = function (argv, done) {
      t.check(false, "no live wallpaper reads in fixture")
    }
    menu.openRoute("root")
    t.waitFor(function () {
      return menu.rowsLoaded
    }, 10000, "real menu loads", function () {
      menu.desktopActions.refreshNow()
      menu.setFilter("action: dnd")
      t.equal(menu.displayModel.count, 1, "action prefix finds DND result")
      t.equal(menu.displayModel.get(0).desktopKey, "action:dnd", "DND uses canonical action identity")
      t.check(menu.hint.indexOf("ENTER APPLY") >= 0, "selected action hint describes applying its change")
      menu.handleKey(key(Qt.Key_Return))
      t.check(menu.opened, "quick action does not close menu")
      t.check(notifications.doNotDisturb && notifications.quietHours, "real menu changes manual DND only")
      t.equal(menu.displayModel.get(0).actionStatus, "confirmed", "confirmed outcome projected into row")
      menu.setFilter("action: audio")
      menu.desktopActions.refreshNow()
      t.equal(menu.displayModel.count, 2, "fresh available outputs become action results")
      menu.selectedIndex = find("action:audio:7:speaker")
      menu.cursorActive = true
      menu.handleKey(key(Qt.Key_Return))
      t.equal(host.dispatched[0], ["output", 7, "speaker"], "selected exact output reaches shared owner")
      t.equal(menu.displayModel.get(menu.selectedIndex).actionStatus, "pending", "dispatch alone shows pending")
      menu.close()
      backend.defaultAudioSink = host.speakers
      t.step(10, function () {
        menu.openRoute("root")
        menu.setFilter("action: audio")
        menu.desktopActions.refreshNow()
        t.equal(menu.displayModel.get(find("action:audio:7:speaker")).actionStatus, "confirmed", "closed-menu completion survives reopen")
        menu.selectedIndex = find("action:audio:8:headphones")
        menu.cursorActive = true
        backend.nodes = {
          values: [host.speakers]
        }
        menu.handleKey(key(Qt.Key_Return))
        t.equal(host.dispatched.length, 1, "removed device cannot dispatch before cached rows refresh")
        menu.desktopActions.refreshNow()
        t.check(menu.selectedIndex === -1 && !menu.cursorActive, "vanished selected action clears cursor")
        backend.nodes = {
          values: [host.speakers, host.headphones]
        }
        menu.desktopActions.refreshNow()
        menu.setFilter("action: headphones")
        menu.handleKey(key(Qt.Key_Return))
        t.step(130, function () {
          t.equal(menu.displayModel.get(0).actionStatus, "failed", "timeout is visible in real result")
          t.equal(menu.recoveryLabel, "Open audio controls", "failure offers explicit recovery destination")
          var recovery = t.findChild(surface, "actionRecovery")
          t.check(recovery && recovery.visible, "recovery control is reachable below results")
          t.check(menu.cardHeight >= recovery.y + recovery.height, "recovery fits card height")
          menu.handleKey(key(Qt.Key_Tab))
          t.check(menu.recoveryFocused, "Tab puts keyboard focus on recovery")
          menu.handleKey(key(Qt.Key_Escape))
          t.check(!menu.recoveryFocused && !!menu.filterText, "Escape leaves recovery without clearing query")
          var recovered = []
          menu.desktopSearch.runner = function (argv) {
            recovered.push(argv)
            return false
          }
          menu.handleKey(key(Qt.Key_Tab))
          menu.handleKey(key(Qt.Key_Return))
          t.equal(recovered[0], ["omarchy-shell", "omarchy.audio", "open"], "recovery uses existing audio destination")
          t.check(menu.opened && menu.notice === "Could not open controls", "refused recovery preserves menu context")
          t.check(menu.desktopActions.activate("action:audio:8:headphones"), "retry submits through current owner")
          menu.desktopActions.audioOwner = null
          t.equal(menu.desktopActions.feedback["action:audio:8:headphones"].status, "failed", "owner removal settles its pending action")
          menu.openDmenu({
            mode: "select",
            options: ["First", "Second"]
          })
          t.check(!menu.displayModel.get(0).actionStatus && !menu.displayModel.get(0).actionMessage, "reused dmenu delegates clear feedback roles")
          t.check(!menu.recoveryLabel, "dmenu never keeps action recovery controls")
          t.done()
        })
      })
    })
  }
}
