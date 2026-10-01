// Real pointer moves over a Bluetooth row's forget button, in a window so
// Qt delivers hover: the button stays shown, keeps its width and its row
// stays hovered for every move over it, instead of hiding and reappearing
// on each motion event (it takes the hover from the row underneath, which
// alone used to keep it shown). Leaving the row hides it again.
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

  FloatingWindow {
    implicitWidth: 400
    implicitHeight: 300
    visible: true

    Bluetooth.BluetoothDropdown {
      id: dropdown
      width: 360
      view: ({
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
          known: [
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
            }
          ],
          discovered: [],
          signals: {},
          emptyText: ""
        })
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
              t.done()
            })
          })
        })
      })
    })
  })
}
