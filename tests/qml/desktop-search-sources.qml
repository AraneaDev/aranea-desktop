// Search controller refresh and activation behavior through injected boundaries.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: shell
  // Argument arrays received by the fake runner.
  property var ran: []
  // Existing host handler requests received by the test.
  property var requests: []
  // Captured asynchronous refresh completions.
  property var pending: []
  // Number of synchronous live snapshot reads.
  property int reads: 0
  // Number of accepted activation signals.
  property int successes: 0
  // Last failure notice emitted by the controller.
  property string failure: ""

  QmlTest {
    id: t
  }
  QtObject {
    id: fakeCompositor
    signal rawEvent(var event)
    property var toplevels: ({
        values: []
      })
    property var workspaces: ({
        values: []
      })
    property var focusedWorkspace: null
  }
  Menu.DesktopSearchSources {
    id: sources
    compositor: fakeCompositor
    fixtureWindows: [
      {
        address: "0xabc",
        title: "Project",
        workspace: {
          id: 2
        }
      }
    ]
    fixtureWorkspaces: [
      {
        id: 2,
        name: "Development",
        windows: 1
      }
    ]
    fixtureFocusedWorkspaceId: 2
    settingsAvailable: true
    appRows: [
      {
        id: "apps.browser",
        kind: "app",
        appId: "browser",
        label: "Browser"
      }
    ]
    menuItems: ({
        vpn: {
          id: "vpn",
          kind: "action",
          label: "VPN"
        }
      })
    snapshotReader: function () {
      shell.reads += 1
      return sources.liveSnapshot()
    }
    runner: function (argv) {
      shell.ran = shell.ran.concat([argv])
      return true
    }
    onAppRequested: function (id, label) {
      shell.requests = shell.requests.concat([["app", id, label]])
    }
    onCommandRequested: function (id) {
      shell.requests = shell.requests.concat([["command", id]])
    }
    onActivated: shell.successes += 1
    onFailed: function (message) {
      shell.failure = message
    }
  }
  Component.onCompleted: {
    t.equal(shell.reads, 0, "inactive construction does not enumerate compositor")
    t.check(!sources.subscribed, "inactive controller has no live subscription")
    fakeCompositor.rawEvent({
      name: "openwindow"
    })
    sources.requestRefresh()
    t.step(130, function () {
      t.equal(shell.reads, 0, "inactive events and refresh requests are gated")
      sources.setActive(true)
      t.waitFor(function () {
        return sources.records.some(function (r) {
          return r.key === "window:0xabc"
        })
      }, 2000, "live snapshot arrives", function () {
        t.check(sources.subscribed, "open connects the live subscription")
        var before = shell.reads
        var revision = sources.revision
        fakeCompositor.rawEvent({
          name: "windowtitle"
        })
        fakeCompositor.rawEvent({
          name: "workspace"
        })
        sources.requestRefresh()
        t.equal(shell.reads, before, "event bursts do not enumerate immediately")
        t.step(130, function () {
          t.equal(shell.reads, before + 1, "100ms timer coalesces event bursts into one read")
          t.equal(sources.revision, revision + 1, "coalesced refresh publishes one revision")
          sources.fixtureWindows = []
          var dispatches = shell.ran.length
          t.check(!sources.activate("window:0xabc"), "removed address is refused before coalesced refresh")
          t.equal(shell.ran.length, dispatches, "removed address dispatches nothing")
          t.equal(shell.failure, "Window is no longer open", "vanished window has clear notice")
          t.check(sources.active, "failure keeps search active")
          sources.activate("app:browser")
          sources.activate("command:vpn")
          t.equal(shell.requests, [["app", "browser", "Browser"], ["command", "vpn"]], "host handler requests preserve app and command identities")
          sources.activate("setting:appearance")
          t.equal(shell.ran[shell.ran.length - 1], ["omarchy-shell", "shell", "summon", "araneadev.settings", '{"section":"appearance"}'], "settings only opens destination")
          sources.fixtureWindows = [
            {
              address: "0x123",
              title: 'Hostile "); bad() --',
              workspace: {
                id: 2
              }
            }
          ]
          sources.activate("window:0x123")
          t.equal(shell.ran[shell.ran.length - 1], ["hyprctl", "dispatch", 'hl.dsp.focus({ window = "address:0x123" })'], "live activation uses fresh raw address and no display text")
          sources.activate("workspace:2")
          t.equal(shell.ran[shell.ran.length - 1], ["hyprctl", "dispatch", 'hl.dsp.focus({ workspace = "2" })'], "workspace activation uses canonical identity")
          sources.refreshReader = function (generation, complete) {
            shell.pending = shell.pending.concat([
              {
                generation: generation,
                complete: complete
              }
            ])
          }
          sources.refreshNow()
          sources.refreshNow()
          var old = shell.pending[0]
          var newest = shell.pending[1]
          newest.complete(newest.generation, {
            compositorAvailable: true,
            windows: [
              {
                address: "0xdef",
                title: "Newest"
              }
            ],
            workspaces: []
          })
          old.complete(old.generation, {
            compositorAvailable: true,
            windows: [
              {
                address: "0xaaa",
                title: "Old"
              }
            ],
            workspaces: []
          })
          t.check(sources.records.some(function (r) {
            return r.key === "window:0xdef"
          }), "newest async generation wins")
          t.check(!sources.records.some(function (r) {
            return r.key === "window:0xaaa"
          }), "late old completion cannot restore stale window")
          dispatches = shell.ran.length
          t.check(!sources.activate("window:0xdef"), "async display snapshot cannot override fresh raw activation snapshot")
          t.equal(shell.ran.length, dispatches, "cached async address dispatches nothing when raw source lacks it")
          sources.refreshNow()
          var closing = shell.pending[2]
          sources.setActive(false)
          t.check(!sources.refreshPending && !sources.subscribed, "close stops refresh timer and subscription")
          closing.complete(closing.generation, {
            compositorAvailable: true,
            windows: [
              {
                address: "0xbbb",
                title: "After close"
              }
            ],
            workspaces: []
          })
          before = shell.reads
          fakeCompositor.rawEvent({
            name: "openwindow"
          })
          sources.requestRefresh()
          t.step(130, function () {
            t.equal(shell.reads, before, "close stops subscriptions and timer reads")
            t.check(!sources.records.some(function (r) {
              return r.type === "window" || r.type === "workspace"
            }), "close clears live records and ignores pending completion")
            t.check(sources.records.some(function (r) {
              return r.type === "app"
            }), "close retains static sources")
            t.check(!sources.activate("setting:appearance"), "inactive controller cannot dispatch")
            sources.refreshReader = null
            sources.compositor = null
            sources.fixtureWindows = null
            sources.fixtureWorkspaces = null
            sources.setActive(true)
            sources.refreshNow()
            t.check(!sources.available, "missing compositor reports unavailable")
            t.equal(sources.records.map(function (r) {
              return r.type
            }), ["app", "command", "setting", "setting", "setting", "setting"], "missing compositor retains app, command and settings")
            sources.menuItems = ({
                vpn: {
                  id: "vpn",
                  kind: "action",
                  label: "VPN"
                },
                empty: {
                  id: "empty",
                  kind: "menu",
                  label: "Empty menu"
                }
              })
            t.check(!sources.records.some(function (r) {
              return r.key === "command:empty"
            }), "existing menu visibility excludes empty destinations")
            sources.snapshotReader = function () {
              throw new Error("Unavailable")
            }
            sources.refreshNow()
            t.check(sources.records.some(function (r) {
              return r.key === "app:browser"
            }), "failed live read retains static sources")
            sources.activate("command:vpn")
            t.equal(shell.requests[shell.requests.length - 1], ["command", "vpn"], "static activation remains usable after failed live read")
            sources.runner = function (argv) {
              return false
            }
            var succeeded = shell.successes
            t.check(!sources.activate("setting:schedule"), "runner rejection refuses activation")
            t.equal(shell.successes, succeeded, "runner failure emits no activated success")
            t.equal(shell.failure, "Could not open target", "runner failure reports notice")
            sources.setActive(false)
            t.done()
          })
        })
      })
    })
  }
}
