// Actual native PasswordlessSudo; only its whole external helper is inert.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "plugins/araneadev.sudo" as Sudo

ShellRoot {
  id: testRoot
  // Native terminal launch captured without opening authentication UI.
  property string launched: ""
  // Probe count before an intentionally delayed refresh.
  property int probes: 0
  QmlTest {
    id: t
  }
  FileView {
    id: activeFile
    path: Quickshell.env("ARANEA_SUDO_FIXTURE_ROOT") + "/active"
    blockLoading: true
  }
  FileView {
    id: callsFile
    path: Quickshell.env("ARANEA_SUDO_FIXTURE_ROOT") + "/calls"
    blockLoading: true
  }
  // Control only the inert command boundary, never the production coalescer.
  Process {
    id: fixtureControl
    property var completed: null
    onExited: function (code) {
      t.equal(code, 0, "native probe fixture control succeeds")
      if (code !== 0) {
        t.done()
        return
      }
      var next = completed
      completed = null
      next()
    }
  }
  // Complete an explicit fixture gate operation before advancing the scenario.
  function controlProbe(action, next) {
    fixtureControl.completed = next
    fixtureControl.command = ["omarchy-sudo-passwordless", "--fixture-" + action]
    fixtureControl.running = true
  }
  FileView {
    id: failFile
    path: Quickshell.env("ARANEA_SUDO_FIXTURE_ROOT") + "/fail-disable"
  }
  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 28
    property color barForeground: "white"
    property color urgent: "red"
    property string fontFamily: "monospace"
    property bool foregroundAnimationEnabled: false
    function run(command) {
      testRoot.launched = command
    }
    function registerClickTarget(target) {
    }
    function unregisterClickTarget(target) {
    }
    function showTooltip(target, text) {
    }
    function hideTooltip(target) {
    }
  }
  Sudo.BarWidget {
    id: widget
    bar: fakeBar
    settings: ({
        nativeSettings: {
          fixture: "native"
        }
      })
  }
  // Observe only the inert whole-helper command log.
  function calls() {
    callsFile.reload()
    return callsFile.text()
  }
  // Count native on-demand status requests without inspecting live grants.
  function probeCount() {
    return calls().split("omarchy-sudo-passwordless --active").length - 1
  }
  Component.onCompleted: t.waitFor(function () {
    return widget.nativeIndicator !== null && probeCount() > 0
  }, 3000, "native sudo indicator loads and probes", function () {
    var native = widget.nativeIndicator
    t.check(String(native).indexOf("PasswordlessSudo") >= 0, "default Loader creates the actual native PasswordlessSudo type")
    t.equal(native.settings.fixture, "native", "native settings reach the real component")
    t.equal(native.indicatorBlock, "single", "standalone indicator stays outside stock active/inactive blocks")
    t.check(native.visible && !native.concealed && native.interactive, "inactive sudo remains visible and clickable")
    t.check(native.dimmed && native.opacity > 0 && native.opacity < 1, "inactive sudo is visibly dimmed")
    native.pressed(Qt.LeftButton)
    t.equal(launched, "omarchy-launch-floating-terminal-with-presentation omarchy-sudo-passwordless", "enable delegates to native authenticated duration picker")
    t.check(!native.granted, "opening or cancelling the native picker does not grant access optimistically")
    activeFile.setText("1")
    widget.refresh()
    t.waitFor(function () {
      return native.granted && !native.dimmed && native.opacity === 1
    }, 3000, "native status observes an enabled grant", function () {
      t.equal(String(native.activeColor), "#ffffff", "enabled icon uses white")
      t.check(!native.dimmed && native.opacity === 1 && native.interactive, "enabled toggle remains fully visible and actionable")
      failFile.setText("1")
      native.pressed(Qt.LeftButton)
      t.waitFor(function () {
        return calls().indexOf("omarchy-notification-send") >= 0
      }, 3000, "native revoke failure is reported", function () {
        t.check(native.granted, "failed revoke retains observed enabled state")
        failFile.setText("")
        // The fixture treats an empty failure marker as cleared below.
        native.pressed(Qt.LeftButton)
        t.waitFor(function () {
          return !native.granted
        }, 3000, "native revoke disables the observed grant", function () {
          t.check(calls().indexOf("omarchy-sudo-passwordless --disable") >= 0, "native toggle dispatches revoke through the whole helper")
          // Observe the real Process lifecycle as well as its command log. A
          // revoke may still have a queued status refresh when granted changes.
          var statusProbe = t.childrenOf(native).filter(function (child) {
            return child.command && child.command.length === 2 && child.command[0] === "omarchy-sudo-passwordless" && child.command[1] === "--active"
          })[0]
          t.check(!!statusProbe, "native status probe process is observable")
          t.waitFor(function () {
            return !statusProbe.running && !native.refreshPending
          }, 2000, "previous native probes drain before the coalescing scenario", function () {
            controlProbe("arm", function () {
              testRoot.probes = probeCount()
              widget.refresh()
              t.waitFor(function () {
                return probeCount() === testRoot.probes + 1 && statusProbe.running
              }, 2000, "held native probe starts", function () {
                widget.refresh()
                widget.refresh()
                widget.refresh()
                t.check(native.refreshPending, "busy refresh burst queues a native probe")
                controlProbe("release", function () {
                  t.waitFor(function () {
                    return probeCount() >= testRoot.probes + 2 && !statusProbe.running && !native.refreshPending
                  }, 4000, "queued native refresh completes and drains", function () {
                    t.equal(probeCount() - testRoot.probes, 2, "busy refreshes coalesce to one pending native probe")
                    t.check(!native.granted && native.interactive && !native.concealed, "expired or inactive state remains an accessible toggle")
                    t.check(calls().indexOf(" --enable") < 0, "fixture never invokes a grant operation")
                    t.done()
                  })
                })
              })
            })
          })
        })
      })
    })
  })
}
