// The shared highlight looks, in a real window with real pointer events:
// a NodeDeviceRow carries the selected highlight only when its host marks
// it selected (never for being lit alone), draws the hover fill only after
// a real pointer move (none under a still pointer, none when the row slides
// under the pointer, none on an informational row), drops it on leaving
// and on the dropdown's layout stamp, and never draws the outline for
// hover; a FilamentPill draws the selected fill when selected and the hover
// fill after a real move; FilamentSwitch and FilamentSlider light the
// shared HoverTint after a real move, and a switch with ownHover off lets
// its row keep the hover, and a switch sliding under a still pointer stays
// unlit; the ForgetButton lights the hover fill once the pointer enters it.
import QtQuick
import QtTest
import Quickshell
import qs.Ui
import "lib"
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  id: host

  QmlTest {
    id: t
  }

  // Synthesizes pointer events (TestCase's mouse helpers), never run as a
  // test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // Whether NAME (an objectName) in ITEM is showing.
  function shows(item, name) {
    var found = t.findChild(item, name)
    return !!found && found.visible
  }

  // Moves the pointer onto ITEM at (X, Y) of it, then really moves it by 4 px.
  function realMove(item, x, y) {
    pointer.mouseMove(item, x, y)
    pointer.mouseMove(item, x + 4, y)
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
    implicitHeight: 400
    visible: true

    Item {
      id: stage
      anchors.fill: parent

      PointerMoveGate {
        id: gate
        // The stage's last layout shift.
        property real layoutChangedAt: 0

        referenceItem: stage
      }

      Aranea.FilamentSwitch {
        id: drifting
        x: 20
        y: 360
      }
      Column {
        x: 20
        y: 10
        width: 360
        spacing: 6

        Aranea.NodeDeviceRow {
          id: lit
          width: 360
          label: "Lit, not selected"
          active: true
          pointerGate: gate
        }
        Aranea.NodeDeviceRow {
          id: chosen
          width: 360
          label: "Selected"
          active: true
          selected: true
          pointerGate: gate
        }
        Aranea.NodeDeviceRow {
          id: info
          width: 360
          label: "Informational"
          interactive: false
          pointerGate: gate
        }
        Aranea.NodeDeviceRow {
          id: switchRow
          width: 360
          label: "Row with a switch"
          pointerGate: gate

          Aranea.FilamentSwitch {
            id: rowSwitch
            ownHover: false
          }
        }
        Row {
          spacing: 12

          Aranea.FilamentPill {
            id: pickedPill
            text: "Picked"
            selected: true
            pointerGate: gate
          }
          Aranea.FilamentPill {
            id: plainPill
            text: "Plain"
            pointerGate: gate
          }
          Aranea.FilamentSwitch {
            id: lone
            anchors.verticalCenter: parent.verticalCenter
          }
        }
        Aranea.FilamentSlider {
          id: slider
          width: 300
          value: 0.5
        }
        Aranea.NodeDeviceRow {
          id: pillRow
          width: 360
          label: "Row with a pill and a forget button"
          pointerGate: gate

          Row {
            spacing: 6

            Aranea.FilamentPill {
              id: rowPill
              text: "Open"
              pointerGate: gate
            }
            Aranea.ForgetButton {
              id: rowForget
              forgettable: true
              hasCursor: true
              pointerGate: gate
            }
          }
        }
        Aranea.ForgetButton {
          id: forget
          forgettable: true
          hasCursor: true
          pointerGate: gate
        }
      }
    }
  }

  Component.onCompleted: run([[400, function () {
        // ---------- Selected highlight ----------
        t.check(shows(chosen, "selectedFill") && shows(chosen, "selectedMarker"), "a selected row draws the selected fill and marker")
        t.check(!shows(lit, "selectedFill") && !shows(lit, "selectedMarker"), "a lit row the host did not select draws neither")
        t.check(shows(pickedPill, "selectedFill") && !shows(plainPill, "selectedFill"), "a selected pill draws the selected fill, a plain one none")
        t.check(!shows(lit, "hoverFill") && !shows(chosen, "hoverFill"), "no hover fill before the pointer moves")

        // ---------- Row hover: a real move only ----------
        gate.reset()
        pointer.mouseMove(lit, 60, lit.height / 2)
      }], [60, function () {
        t.check(!shows(lit, "hoverFill"), "the first sample under the pointer lights nothing")
        pointer.mouseMove(lit, 64, lit.height / 2)
      }], [60, function () {
        t.check(shows(lit, "hoverFill"), "a real move onto a row draws its hover fill")
        t.check(t.findChild(lit, "cursorOutline").border.width === 0, "hover never draws the outline")
        realMove(chosen, 60, chosen.height / 2)
      }], [60, function () {
        t.check(shows(chosen, "hoverFill") && !shows(lit, "hoverFill"), "moving on lights the next row and drops the last")
        t.check(shows(chosen, "selectedFill"), "the selected highlight stays under the hover fill")
        gate.layoutChangedAt = Date.now()
      }], [40, function () {
        t.check(!shows(chosen, "hoverFill"), "a layout stamp drops the hover fill under a still pointer")
        realMove(info, 60, info.height / 2)
      }], [60, function () {
        t.check(!shows(info, "hoverFill"), "an informational row draws no hover fill")

        // ---------- A switch on a self-lit row ----------
        realMove(rowSwitch, rowSwitch.width / 2, rowSwitch.height / 2)
      }], [60, function () {
        t.check(shows(switchRow, "hoverFill"), "a switch with ownHover off lets its row keep the hover fill")
        t.check(!t.findChild(rowSwitch, "hoverFill").visible, "and draws none of its own")

        // ---------- Pills, a lone switch, the slider ----------
        realMove(plainPill, plainPill.width / 2, plainPill.height / 2)
      }], [60, function () {
        t.check(shows(plainPill, "hoverFill") && !shows(pickedPill, "hoverFill"), "a real move onto a pill draws its hover fill")
        t.check(t.findChild(plainPill, "cursorOutline").border.width === 0, "and never its outline")
        pointer.mouseMove(lone, lone.width / 2, lone.height / 2)
      }], [60, function () {
        t.check(!shows(lone, "hoverFill") && !shows(plainPill, "hoverFill"), "entering a switch lights nothing until the pointer moves on it")
        pointer.mouseMove(lone, lone.width / 2 + 4, lone.height / 2)
      }], [60, function () {
        t.check(shows(lone, "hoverFill"), "then a real move lights the switch")
        realMove(slider, 40, slider.height / 2)
      }], [60, function () {
        t.check(shows(slider, "hoverFill") && !shows(lone, "hoverFill"), "a real move lights the slider and leaving drops the switch's fill")

        // ---------- Forget button ----------
        realMove(forget, forget.width / 2, forget.height / 2)
      }], [60, function () {
        t.check(forget.pointerHovered && Qt.colorEqual(t.findChild(forget, "forgetBorder").color, Aranea.DesignTokens.hoverFill), "the forget button lights the hover fill once entered")
        pointer.mouseMove(stage, 400, 390)
      }], [60, function () {
        t.check(!forget.pointerHovered && !shows(slider, "hoverFill"), "leaving drops every hover fill")

        // ---------- Gated controls on a gated row (one shared gate) ----------
        realMove(pillRow, 40, pillRow.height / 2)
      }], [60, function () {
        t.check(shows(pillRow, "hoverFill"), "the gated row lights first")
        var p = rowPill.mapToItem(pillRow, rowPill.width / 2, rowPill.height / 2)
        pointer.mouseMove(pillRow, p.x, p.y)
      }], [60, function () {
        var p = rowPill.mapToItem(pillRow, rowPill.width / 2, rowPill.height / 2)
        pointer.mouseMove(pillRow, p.x + 3, p.y)
      }], [60, function () {
        t.check(shows(rowPill, "hoverFill"), "a gated pill on a gated row lights on a real move")
        var f = rowForget.mapToItem(pillRow, rowForget.width / 2, rowForget.height / 2)
        pointer.mouseMove(pillRow, f.x, f.y)
      }], [60, function () {
        var f = rowForget.mapToItem(pillRow, rowForget.width / 2, rowForget.height / 2)
        pointer.mouseMove(pillRow, f.x + 3, f.y)
      }], [60, function () {
        t.check(rowForget.pointerHovered && !shows(rowPill, "hoverFill"), "a gated forget button on a gated row lights too, and the pill's fill drops")
        pointer.mouseMove(stage, 400, 390)

        // ---------- Content sliding under a still pointer ----------
        pointer.mouseMove(stage, 200, 368)
      }], [60, function () {
        pointer.mouseMove(stage, 204, 368)
      }], [60, function () {
        drifting.x = 190
      }], [80, function () {
        t.check(!shows(drifting, "hoverFill"), "a switch sliding under a still pointer stays unlit")
        pointer.mouseMove(stage, 200, 368)
      }], [60, function () {
        pointer.mouseMove(stage, 204, 368)
      }], [60, function () {
        t.check(shows(drifting, "hoverFill"), "a real move over it lights it")
      }]])
}
