// The Updates dropdown's Filament rules, in a real window with real pointer
// events: the mint outline shows only with the keyboard and never on hover
// (UpdateLogic.moveCursor reveals the pill cursor on its first key, then
// moves and wraps it; a real pointer move onto a pill places the cursor
// there, hidden); the status row's node and tone word read warn or ok
// (UpdateLogic.statusRow); the Refresh pill reads "Refreshing..." and
// pulses busy while checking, and ignores a click then; and a click on a
// pill right after this panel's layout shifts (the group list appearing)
// is refused until it settles, same as the other Filament dropdowns.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.updates" as Updates
import "plugins/araneadev.updates/UpdateLogic.js" as UpdateLogic
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  id: host

  QmlTest {
    id: t
  }

  // The host's cursor index, as UpdatePanelHost.cursorIndex.
  property int cursorIndex: 0
  // The host's keyboard mode, as UpdatePanelHost.keyboardCursor.
  property bool keyboard: false
  // Actions reported by the panel, as [name], in emission order.
  property var actions: []
  // The pointer's resting point, for the two-phase hover checks.
  property var stillPoint: null

  // Synthesizes pointer events (TestCase's mouse helpers), never run as a
  // test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // Moves the cursor DY pills (UpdateLogic.moveCursor), as a host's
  // onMoveRequested does.
  function move(dy) {
    var next = UpdateLogic.moveCursor(host.cursorIndex, host.keyboard, dy)
    host.cursorIndex = next.index
    host.keyboard = next.keyboardCursor
  }

  // How many pills draw the mint outline.
  function outlined() {
    return t.findChildren(panel, "cursorOutline").filter(function (o) {
      return o.border.width > 0
    }).length
  }

  // Runs STEPS ([delay, fn] pairs) one after another, then finishes.
  function run(steps) {
    if (steps.length === 0) {
      t.done()
      return
    }
    t.step(steps[0][0], function () {
      steps[0][1]()
      run(steps.slice(1))
    })
  }

  FloatingWindow {
    implicitWidth: 420
    implicitHeight: 300
    visible: true

    Updates.UpdatePanel {
      id: panel
      x: 20
      y: 10
      width: 380
      status: ({
          count: 0,
          rebootRequired: true,
          error: "",
          groups: []
        })
      checking: false
      cursorIndex: host.cursorIndex
      keyboardCursor: host.keyboard
      onOpenUpdater: host.actions = host.actions.concat([["openUpdater"]])
      onRefresh: host.actions = host.actions.concat([["refresh"]])
      onPillHovered: function (index) {
        host.keyboard = false
        host.cursorIndex = index
      }
    }
  }

  Component.onCompleted: run([[400, function () {
        // ---------- Status row ----------
        t.equal(t.findChild(panel, "statusTitle").text, "Reboot required", "a pending reboot reads as a warning")
        t.equal(t.findChild(panel, "statusDetail").text, "warn", "the trailing word is warn")
        t.check(Qt.colorEqual(t.findChild(panel, "statusNode").color, Aranea.DesignTokens.attention), "the node is tinted amber for warn")
        panel.status = ({
            count: 2,
            rebootRequired: false,
            error: "",
            groups: []
          })
        t.equal(t.findChild(panel, "statusTitle").text, "Up to date", "updates waiting with no reboot still reads ok")
        t.equal(t.findChild(panel, "statusSubtitle").text, "2 updates available", "the count line pluralizes")
        t.check(Qt.colorEqual(t.findChild(panel, "statusNode").color, Aranea.DesignTokens.ceremony), "the node is tinted mint/ceremony for ok")

        // ---------- Header caption ----------
        t.equal(t.findChild(panel, "headerCaption").text.toLowerCase(), "", "no caption before the first check")
        panel.status = ({
            count: 0,
            rebootRequired: false,
            error: "",
            checkedAt: new Date(2026, 8, 30, 8, 58).getTime()
          })
        t.equal(t.findChild(panel, "headerCaption").text.toLowerCase(), "checked 08:58", "the caption states the last check")
        panel.checking = true
        t.equal(t.findChild(panel, "headerCaption").text.toLowerCase(), "checking…", "checking wins over a settled caption")

        // ---------- Outline: keyboard only ----------
        t.equal(outlined(), 0, "no outline before the keyboard")
        host.move(1)
        t.check(t.findChild(panel, "openUpdaterPill").hasCursor && outlined() === 1, "the first key reveals the outline on Open updater, without moving")
        host.move(1)
        t.check(t.findChild(panel, "refreshPill").hasCursor && !t.findChild(panel, "openUpdaterPill").hasCursor && outlined() === 1, "a later key moves the cursor to Refresh")
        host.move(1)
        t.check(t.findChild(panel, "openUpdaterPill").hasCursor, "the cursor wraps back to Open updater")
        host.move(-1)
        t.check(t.findChild(panel, "refreshPill").hasCursor, "and wraps the other way too")

        // ---------- Refresh busy ----------
        t.equal(t.findChild(panel, "refreshPill").text, "Refreshing…", "the busy pill reads Refreshing")
        t.check(t.findChild(panel, "refreshPill").busy, "and pulses busy")
        actions = []
        pointer.mouseClick(t.findChild(panel, "refreshPill"))
        t.equal(actions.length, 0, "a click on a busy Refresh pill is ignored")
        panel.checking = false
      }], [350, function () {
        // ---------- Settled clicks ----------
        actions = []
        pointer.mouseClick(t.findChild(panel, "refreshPill"))
        t.equal(JSON.stringify(actions), JSON.stringify([["refresh"]]), "a settled click on Refresh reports it")
        actions = []
        pointer.mouseClick(t.findChild(panel, "openUpdaterPill"))
        t.equal(JSON.stringify(actions), JSON.stringify([["openUpdater"]]), "and Open updater reports its own action")

        // The group list appearing pushes the footer down under a still
        // pointer; the click that follows, in the next step, is tested
        // once the relayout has actually happened.
        actions = []
        panel.status = ({
            count: 2,
            rebootRequired: false,
            error: "",
            groups: [
              {
                source: "system",
                count: 2,
                items: ["a", "b"]
              }
            ]
          })
      }], [30, function () {
        pointer.mouseClick(t.findChild(panel, "refreshPill"))
        t.equal(actions.length, 0, "a click right after the group list appears is ignored")
      }], [350, function () {
        pointer.mouseClick(t.findChild(panel, "refreshPill"))
        t.equal(JSON.stringify(actions), JSON.stringify([["refresh"]]), "a click 300 ms after the shift is accepted")

        // ---------- Hover never outlines ----------
        host.keyboard = true
        host.cursorIndex = 0
        t.equal(outlined(), 1, "the keyboard outline is showing")
        panel.disarmPointer()
        stillPoint = t.findChild(panel, "refreshPill").mapToItem(panel, t.findChild(panel, "refreshPill").width / 2, t.findChild(panel, "refreshPill").height / 2)
        pointer.mouseMove(panel, stillPoint.x, stillPoint.y)
      }], [80, function () {
        pointer.mouseMove(panel, stillPoint.x + 4, stillPoint.y)
      }], [120, function () {
        t.check(!host.keyboard && host.cursorIndex === 1, "a real pointer move over Refresh places the cursor there")
        t.equal(outlined(), 0, "and hover never outlines a pill")
      }]])
}
