// Real pointer moves over a Bluetooth row's forget button, in a window so
// Qt delivers hover: the button stays shown, keeps its width and its row
// stays hovered for every move over it, instead of hiding and reappearing
// on each motion event (it takes the hover from the row underneath, which
// alone used to keep it shown). Leaving the row hides it again. Entering
// the forget button's hover action goes through the view's gate (a still
// pointer under a button that slides into place never moves the keyboard
// cursor onto it), but leaving it, and the button's own shown/bright
// visuals, stay ungated.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.bluetooth" as Bluetooth

ShellRoot {
  QmlTest {
    id: t
  }

  // Visibility/width changes of the forget button and the actions the
  // dropdown emitted since the last reset, in order.
  property var events: []

  // Three known devices, so removing the first slides the others up one
  // row under a pointer that never moved.
  function buildView(known) {
    return {
      glyph: "",
      caption: "",
      enabled: true,
      hasAdapter: true,
      toggleHint: "",
      headerCursor: false,
      scanning: false,
      cursor: {
        active: false,
        section: "",
        index: -1,
        action: false
      },
      connected: [],
      known: known,
      discovered: [],
      signals: {},
      emptyText: ""
    }
  }

  FloatingWindow {
    implicitWidth: 400
    implicitHeight: 300
    visible: true

    Bluetooth.BluetoothDropdown {
      id: dropdown
      width: 360
      view: buildView([
        {
          key: "BB:1",
          label: "MX Master 3S",
          glyph: "",
          detail: "",
          busy: false,
          forgettable: true
        },
        {
          key: "BB:2",
          label: "Pixel 8",
          glyph: "",
          detail: "",
          busy: false,
          forgettable: true
        },
        {
          key: "BB:3",
          label: "Keychron K3",
          glyph: "",
          detail: "",
          busy: false,
          forgettable: true
        }
      ])
      onAction: function (name, arg) {
        events.push(name + ":" + JSON.stringify(arg))
      }
    }
  }

  // Synthesizes the pointer events (TestCase's mouseMove), never run as a test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  Component.onCompleted: t.step(300, function () {
    var paired = t.findChild(dropdown, "pairedSection")
    var row = t.findChildren(paired, "deviceRow")[0]
    var button = t.findChildren(paired, "forgetButton")[0]
    button.visibleChanged.connect(function () {
      events.push("visible=" + button.visible)
    })
    button.widthChanged.connect(function () {
      events.push("width=" + button.width)
    })

    pointer.mouseMove(row, 40, row.height / 2)
    t.step(100, function () {
      t.check(row.hovered && button.visible && button.width > 0, "hovering the row shows its forget button")
      var at = button.mapToItem(row, button.width / 2, button.height / 2)
      events = []
      pointer.mouseMove(row, at.x, at.y)
      t.step(100, function () {
        pointer.mouseMove(row, at.x + 1, at.y)
        t.step(100, function () {
          pointer.mouseMove(row, at.x + 2, at.y)
          t.step(100, function () {
            var flips = events.filter(function (e) {
              return e.indexOf("visible=") === 0 || e.indexOf("width=") === 0
            })
            t.equal(flips, [], "moving over the forget button never hides or resizes it")
            t.check(button.visible && button.width > 0, "the forget button is still shown under the pointer")
            t.equal(events.filter(function (e) {
              return e.indexOf("hover:") === 0
            }), ["hover:{\"section\":\"known\",\"index\":0,\"action\":true}"], "entering the button reports one action hover and nothing per move")
            pointer.mouseMove(row, at.x, row.height + 60)
            t.step(100, function () {
              t.check(!button.visible && button.width === 0, "leaving the row hides the forget button")

              // Hover row 1's (Pixel 8) forget button for real, then remove
              // row 0 without moving the pointer: row 2 (Keychron K3)
              // slides up to occupy row 1's old screen position. A
              // compositor redelivers the pointer's last position as a new
              // event when the scene changes underneath it, so the test
              // replays that same absolute point explicitly rather than
              // relying on an implicit re-hover. Entering the button's
              // hover action is gated (no synthetic cursor steal from that
              // replay), but leaving it is not.
              var rows = t.findChildren(paired, "deviceRow")
              var row1 = rows[1]
              var button1 = t.findChildren(paired, "forgetButton")[1]
              pointer.mouseMove(row1, 40, row1.height / 2)
              t.step(100, function () {
                var at1 = button1.mapToItem(row1, button1.width / 2, button1.height / 2)
                // A stable point in dropdown coordinates: row 1's screen
                // slot doesn't move when row 0 is removed, only its content.
                var stable = button1.mapToItem(dropdown, button1.width / 2, button1.height / 2)
                events = []
                pointer.mouseMove(row1, at1.x, at1.y)
                t.step(100, function () {
                  t.equal(events.filter(function (e) {
                    return e.indexOf("hover:") === 0
                  }), ["hover:{\"section\":\"known\",\"index\":1,\"action\":true}"], "a real hover on row 1's forget button reports its action hover")
                  events = []
                  dropdown.view = buildView([
                    {
                      key: "BB:2",
                      label: "Pixel 8",
                      glyph: "",
                      detail: "",
                      busy: false,
                      forgettable: true
                    },
                    {
                      key: "BB:3",
                      label: "Keychron K3",
                      glyph: "",
                      detail: "",
                      busy: false,
                      forgettable: true
                    }
                  ])
                  t.step(100, function () {
                    // Replay the same absolute point: the button now under
                    // it belongs to a different device, but the pointer
                    // itself never moved.
                    pointer.mouseMove(dropdown, stable.x, stable.y)
                    t.step(100, function () {
                      t.equal(events.filter(function (e) {
                        return e.indexOf("hover:") === 0 && e.indexOf("\"action\":true") !== -1
                      }), [], "a forget button sliding under a still pointer doesn't take the cursor")
                      var buttonAfterSlide = t.findChildren(paired, "forgetButton")[1]
                      t.check(buttonAfterSlide.visible, "the slid-in button is still shown (its row is still hovered)")
                      events = []
                      var afterSlide = t.findChildren(paired, "deviceRow")[1]
                      // Leave, for real: dropping the action focus is never
                      // gated, whether or not the entering transition above
                      // was suppressed.
                      pointer.mouseMove(afterSlide, afterSlide.width - 20, afterSlide.height + 60)
                      t.step(100, function () {
                        t.check(events.filter(function (e) {
                          return e.indexOf("hover:") === 0 && e.indexOf("\"leave\":true") !== -1
                        }).length > 0, "leaving the forget button still reports leave, ungated")
                        events = []
                        // Re-enter for real: the row first (a separate real
                        // move, well outside the button), then the button
                        // itself; the gate isn't stuck suppressing it.
                        pointer.mouseMove(afterSlide, 40, afterSlide.height / 2)
                        t.step(100, function () {
                          pointer.mouseMove(dropdown, stable.x, stable.y)
                          t.step(100, function () {
                            t.check(events.filter(function (e) {
                              return e.indexOf("hover:") === 0 && e.indexOf("\"action\":true") !== -1
                            }).length > 0, "a real re-entry onto the slid-in button fires its action hover again")
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
        })
      })
    })
  })
}
