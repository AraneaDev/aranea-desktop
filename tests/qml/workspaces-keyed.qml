// The Workspaces dropdown's Filament rules, in a real window with real
// pointer events: the mint outline shows only with the keyboard and never
// on hover (WorkspaceModel.cursorMove reveals the row cursor on its first
// key, then moves and wraps it; Enter as the first key only reveals it
// too); a real pointer move onto a row draws its hover fill but never
// moves the cursor or the outline; the current workspace carries the
// selected highlight; rows are keyed by workspace id and a keyed action
// whose row no longer carries that id is refused; the rows stay the same
// delegates across a refresh that hands over a new (but equal) array, and
// a click right after the rows change is refused until it settles. A
// second, static panel (panel2) covers the two state-only cases: an urgent
// workspace's row is tinted (not only its "attention" detail text), and a
// workspace with open windows shows their titles underneath.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.workspaces" as Workspaces
import "plugins/araneadev.workspaces/WorkspaceModel.js" as WorkspaceModel
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  id: host

  QmlTest {
    id: t
  }

  // The host's cursor key, as WorkspacePanelHost.cursorKey.
  property string cursorKey: ""
  // The host's keyboard mode, as WorkspacePanelHost.keyboardCursor.
  property bool keyboard: false
  // Workspaces focused, as [id], in order.
  property var focused: []
  // Hovered row indexes, in order.
  property var hovered: []
  // The layout stamp a step compares against.
  property real stampBefore: 0
  // The rows' delegates a step compares against.
  property var rowsBefore: []
  // The pointer's resting point.
  property var stillPoint: null

  // Synthesizes pointer events (TestCase's mouse helpers), never run as a
  // test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // A workspace row fixture: ID, window count and whether it is active.
  function workspace(id, windows, active) {
    return {
      id: id,
      name: String(id),
      windows: windows,
      active: active
    }
  }

  // The workspaces in their first order.
  function firstRows() {
    return [workspace(1, 1, true), workspace(2, 0, false), workspace(3, 2, false)]
  }

  // How many rows draw the mint outline.
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

    Workspaces.WorkspacePanel {
      id: panel
      x: 20
      y: 10
      width: 380
      workspaceStates: firstRows()
      cursorIndex: WorkspaceModel.outlineIndex(panel.workspaceStates, host.cursorKey, host.keyboard)
      onFocusWorkspace: function (id) {
        host.keyboard = false
        host.focused = host.focused.concat([id])
      }
      onRowHovered: function (index) {
        host.hovered = host.hovered.concat([index])
      }
    }

    // State-only panel: an urgent row (index 0, no titles) and a row with
    // open windows (index 1, no urgency). No pointer/keyboard driving.
    Workspaces.WorkspacePanel {
      id: panel2
      x: 20
      y: 260
      width: 380
      workspaceStates: [
        {
          id: 9,
          name: "9",
          windows: 1,
          active: false,
          urgent: true,
          windowLabels: []
        },
        {
          id: 10,
          name: "10",
          windows: 2,
          active: false,
          urgent: false,
          windowLabels: ["kitty", "firefox"]
        }
      ]
    }
  }

  Component.onCompleted: run([[400, function () {
        // ---------- Header ----------
        t.equal(t.findChild(panel, "headerCaption").text.toLowerCase(), "3 open", "the caption counts the shown workspaces")

        // ---------- Outline: keyboard only ----------
        t.equal(outlined(), 0, "no outline before the keyboard")
        var first = WorkspaceModel.cursorPress(panel.workspaceStates, "", false)
        t.check(first.key === "1" && first.keyboard && first.row === null, "Enter as the first key only reveals the cursor on the first row")
        t.check(t.findChild(panel.rowAt(0), "selectedFill").visible && t.findChild(panel.rowAt(0), "selectedMarker").visible, "the current workspace carries the selected highlight")
        t.check(!t.findChild(panel.rowAt(1), "selectedFill").visible && !t.findChild(panel.rowAt(2), "selectedFill").visible, "other workspaces do not")
        t.check(!t.findChild(panel.rowAt(0), "hoverFill").visible, "no hover fill without a pointer")
        var next = WorkspaceModel.cursorMove(panel.workspaceStates, host.cursorKey, host.keyboard, 1)
        host.cursorKey = next.key
        host.keyboard = next.keyboard
        t.check(panel.rowAt(0).hasCursor && outlined() === 1, "the first key reveals the outline on the first row, without moving")
        t.check(panel.rowAt(0).active, "the current workspace's row is lit")
        t.check(!panel.rowAt(1).active, "a non-current workspace's row is not lit")

        // ---------- Row text ----------
        t.equal(panel.rowAt(0).label, "Workspace 1", "a row is labelled by its workspace name")
        t.equal(panel.rowAt(0).detail, "1 window · current", "the current workspace's detail names it")
        t.equal(panel.rowAt(1).detail, "empty", "an empty workspace reads empty")
        t.equal(panel.rowAt(2).detail, "2 windows", "the count pluralizes")

        // ---------- Urgent tint and window titles (panel2) ----------
        t.equal(panel2.rowAt(0).detail, "1 window · attention", "an urgent row's detail names it")
        t.check(Qt.colorEqual(panel2.rowAt(0).nodeColor, Aranea.DesignTokens.urgent), "an urgent row's node colour is the urgent token")
        t.check(Qt.colorEqual(t.findChild(panel2.rowAt(0), "nodeMarker").color, Aranea.DesignTokens.urgent), "an urgent row's marker is lit urgent even though it is not current")
        var titlesLines = t.findChildren(panel2, "workspaceTitles")
        t.check(!titlesLines[0].visible, "a row with no open windows shows no titles line")
        t.check(titlesLines[1].visible && titlesLines[1].text === "kitty · firefox", "a row with open windows shows their titles")
        t.check(!Qt.colorEqual(panel2.rowAt(1).nodeColor, Aranea.DesignTokens.urgent), "a non-urgent row's node colour is unaffected")

        // ---------- Stable rows across a refresh ----------
        rowsBefore = [panel.rowAt(0), panel.rowAt(1), panel.rowAt(2)]
        stampBefore = panel.layoutChangedAt
        panel.workspaceStates = firstRows()
        t.check(panel.rowAt(0) === rowsBefore[0] && panel.rowAt(1) === rowsBefore[1] && panel.rowAt(2) === rowsBefore[2], "a refresh with a new array keeps every row delegate")
        t.equal(panel.layoutChangedAt, stampBefore, "an equal list rebuilt does not stamp")

        // ---------- Keyed actions ----------
        panel.activateRow(2, "1")
        t.equal(focused.length, 0, "a keyed action whose row does not carry the key is refused")
        panel.activateRow(0, "1")
        t.equal(JSON.stringify(focused), JSON.stringify([1]), "the matching row is accepted")
        focused = []
        pointer.mouseClick(panel.rowAt(0), 60, panel.rowAt(0).height / 2)
        t.equal(JSON.stringify(focused), JSON.stringify([1]), "a settled click reports its row's workspace id")

        // ---------- Settle after the rows re-sort ----------
        focused = []
        stampBefore = panel.layoutChangedAt
        panel.workspaceStates = firstRows().reverse()
        t.check(panel.layoutChangedAt > stampBefore, "a re-sort stamps the layout")
        t.check(panel.rowAt(0) === rowsBefore[0] && panel.rowAt(1) === rowsBefore[1] && panel.rowAt(2) === rowsBefore[2], "a re-sort keeps the delegates too")
        pointer.mouseClick(panel.rowAt(0), 60, panel.rowAt(0).height / 2)
        t.equal(focused.length, 0, "a click right after a re-sort is refused")
      }], [350, function () {
        pointer.mouseClick(panel.rowAt(0), 60, panel.rowAt(0).height / 2)
        t.equal(JSON.stringify(focused), JSON.stringify([3]), "once settled, the re-sorted row takes the click with its own workspace id")

        // ---------- Hover never outlines ----------
        host.keyboard = true
        host.cursorKey = "3"
        t.equal(outlined(), 1, "the keyboard outline is showing")
        panel.disarmPointer()
        stillPoint = panel.rowAt(2).mapToItem(panel, 60, panel.rowAt(2).height / 2)
        pointer.mouseMove(panel, stillPoint.x, stillPoint.y)
      }], [80, function () {
        pointer.mouseMove(panel, stillPoint.x + 4, stillPoint.y)
      }], [200, function () {
        t.check(hovered.indexOf(2) >= 0, "a real move over a row reports hover")
        t.check(t.findChild(panel.rowAt(2), "hoverFill").visible, "a real move draws the hover fill on that row")
        t.check(!t.findChild(panel.rowAt(0), "hoverFill").visible && !t.findChild(panel.rowAt(1), "hoverFill").visible, "and only there")
        t.equal(host.cursorKey, "3", "hover never moves the cursor key")
        t.check(outlined() === 1 && panel.rowAt(0).hasCursor && !panel.rowAt(2).hasCursor, "the outline stays on the keyboard's row")
        var press = WorkspaceModel.cursorPress(panel.workspaceStates, host.cursorKey, host.keyboard)
        t.check(!!press.row && press.row.id === 3, "Enter acts on the outlined row, not the hovered one")
        panel.workspaceStates = firstRows()
      }], [40, function () {
        t.check(!t.findChild(panel.rowAt(2), "hoverFill").visible, "the rows changing under a still pointer drop the hover fill")
      }]])
}
