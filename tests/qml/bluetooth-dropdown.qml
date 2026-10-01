// The Aranea Bluetooth view, driven by a plain view object: Connected,
// Paired and Available sections show and hide with the fixture lists, the
// scanning pulse tracks view.scanning, device glyphs and busy pulses come
// from the fixture, forget shows only for forgettable rows, available rows
// emit primary and right-click emits secondary, the signal glow follows
// the separate signals map without rebuilding rows, the keyboard cursor
// outlines exactly one row when active, every trailing element ends on
// one right content edge, and a missing adapter hides the lists behind
// the empty text.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.bluetooth" as Bluetooth

ShellRoot {
  QmlTest {
    id: t
  }

  // Actions reported by full's action signal, in emission order.
  property var actions: []

  Bluetooth.BluetoothDropdown {
    id: full
    width: 360
    view: ({
        glyph: String.fromCodePoint(0xf00af),
        caption: "Herding headsets",
        enabled: true,
        hasAdapter: true,
        toggleHint: "Turn Bluetooth off",
        headerCursor: false,
        scanning: true,
        cursor: {
          active: false,
          section: "connected",
          index: 0,
          action: false
        },
        connected: [
          {
            key: "AA:1",
            label: "WH-1000XM4",
            glyph: String.fromCodePoint(0xf02cb),
            detail: "82%",
            busy: false,
            forgettable: true
          }
        ],
        known: [
          {
            key: "BB:1",
            label: "MX Master 3S",
            glyph: String.fromCodePoint(0xf037d),
            detail: "",
            busy: false,
            forgettable: true
          },
          {
            key: "BB:2",
            label: "Pixel 8",
            glyph: String.fromCodePoint(0xf03f2),
            detail: "",
            busy: false,
            forgettable: true
          },
          {
            key: "BB:3",
            label: "Keychron K3",
            glyph: String.fromCodePoint(0xf030c),
            detail: "Connecting…",
            busy: true,
            forgettable: true
          }
        ],
        discovered: [
          {
            key: "CC:1",
            label: "JBL Flip 6",
            glyph: String.fromCodePoint(0xf04c3),
            detail: "",
            busy: false,
            forgettable: false
          },
          {
            key: "CC:2",
            label: "Xbox Wireless Controller",
            glyph: String.fromCodePoint(0xf0297),
            detail: "",
            busy: false,
            forgettable: false
          },
          {
            key: "CC:3",
            label: "Galaxy Buds2",
            glyph: String.fromCodePoint(0xf00af),
            detail: "",
            busy: false,
            forgettable: false
          }
        ],
        signals: {
          "CC:1": 3,
          "CC:2": 1
        },
        emptyText: ""
      })
    onAction: function (name, arg) {
      actions.push([name, arg])
    }
  }

  Bluetooth.BluetoothDropdown {
    id: bare
    width: 360
    view: ({
        glyph: "",
        caption: "",
        enabled: false,
        hasAdapter: false,
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
        known: [],
        discovered: [],
        signals: {},
        emptyText: "No Bluetooth adapter"
      })
  }

  // VIEW with only signals replaced by SIGNALS; every row array is reused.
  function signalsTick(view, signals) {
    var next = {}
    for (var key in view)
      next[key] = view[key]
    next.signals = signals
    return next
  }

  // VIEW with the cursor set to ACTIVE, SECTION, INDEX and ACTION.
  function cursorTick(view, active, section, index, action) {
    var next = {}
    for (var key in view)
      next[key] = view[key]
    next.cursor = {
      active: active,
      section: section,
      index: index,
      action: action
    }
    return next
  }

  // How many cursor outlines in ITEM are drawn (a border or a fill).
  function litOutlines(item) {
    return t.findChildren(item, "cursorOutline").filter(function (o) {
      return o.visible && (o.border.width > 0 || o.color.a > 0)
    }).length
  }

  // Right edge of ITEM in full's coordinates.
  function rightEdge(item) {
    return item.mapToItem(full, item.width, 0).x
  }

  Component.onCompleted: t.step(300, function () {
    var connected = t.findChild(full, "connectedSection")
    var paired = t.findChild(full, "pairedSection")
    var available = t.findChild(full, "availableSection")
    t.check(connected !== null && connected.visible, "Connected shows with a device")
    t.check(paired !== null && paired.visible, "Paired shows with devices")
    t.check(available !== null && available.visible, "Available shows while scanning with devices")

    var connectedRows = t.findChildren(connected, "deviceRow")
    var pairedRows = t.findChildren(paired, "deviceRow")
    var availableRows = t.findChildren(available, "deviceRow")
    t.equal(connectedRows.length, 1, "one connected device")
    t.equal(pairedRows.length, 3, "three paired devices")
    t.equal(availableRows.length, 3, "three available devices")

    // Glyphs come straight from the fixture rows.
    t.equal(connectedRows[0].glyph, full.view.connected[0].glyph, "connected row glyph comes from the fixture")
    t.equal(pairedRows[1].glyph, full.view.known[1].glyph, "paired row glyph comes from the fixture")
    t.equal(availableRows[0].glyph, full.view.discovered[0].glyph, "available row glyph comes from the fixture")

    // Only the connected device is marked active (its node lights).
    t.check(connectedRows[0].active, "the connected row is marked active")
    t.check(!pairedRows[0].active && !availableRows[0].active, "paired and available rows are not active")

    // The scanning pulse tracks view.scanning.
    var pulse = t.findChild(full, "scanPulse")
    t.check(pulse !== null && pulse.visible, "the pulse runs while scanning")
    t.check(!t.findChild(bare, "scanPulse").visible, "the pulse is hidden without scanning")

    // Busy rows (Keychron K3, index 2 in Paired) run their breathing pulse.
    var busyPulse = t.findChildren(pairedRows[2], "busyPulse")[0]
    var idlePulse = t.findChildren(pairedRows[0], "busyPulse")[0]
    t.check(busyPulse !== undefined && busyPulse.running, "a busy row runs its pulse")
    t.check(idlePulse !== undefined && !idlePulse.running, "an idle row's pulse does not run")

    // Forget shows only for forgettable rows, driven by the keyboard cursor
    // (pointer hover can't be synthesized in this offscreen harness).
    var connectedForget = t.findChildren(connected, "forgetButton")
    var availableForget = t.findChildren(available, "forgetButton")
    t.check(!connectedForget[0].visible, "forget hides off cursor even on a forgettable row")
    t.check(!availableForget[0].visible, "available rows are never forgettable")
    full.view = cursorTick(full.view, true, "connected", 0, false)
    t.step(50, function () {
      var connectedForgetOnCursor = t.findChildren(connected, "forgetButton")
      t.check(connectedForgetOnCursor[0].visible, "forget shows once the cursor sits on a forgettable row")
      connectedForgetOnCursor[0].activate()
      t.equal(JSON.stringify(actions[actions.length - 1]), JSON.stringify(["forget",
        {
          section: "connected",
          index: 0
        }
      ]), "the forget button emits forget for its row")

      // Available rows emit primary when chosen.
      availableRows[1].activate()
      t.equal(JSON.stringify(actions[actions.length - 1]), JSON.stringify(["primary",
        {
          section: "discovered",
          index: 1
        }
      ]), "choosing an available row emits primary")

      // Right-click emits secondary.
      var pairedSecondary = t.findChildren(paired, "secondaryArea")
      pairedSecondary[1].clicked(null)
      t.equal(JSON.stringify(actions[actions.length - 1]), JSON.stringify(["secondary",
        {
          section: "known",
          index: 1
        }
      ]), "right-clicking a row emits secondary")

      // Signal glow levels come from the separate signals map.
      t.equal(availableRows[0].signal, 3, "a strong signal reaches its row")
      t.equal(availableRows[1].signal, 1, "a weak signal reaches its row")
      t.equal(availableRows[2].signal, -1, "a device with no signal entry shows none")
      t.equal(connectedRows[0].signal, -1, "connected rows never show a signal glow")

      // A signals-only change reuses the view object but not the row
      // arrays; the row delegates must survive it (an in-progress drag or
      // click would otherwise be lost), as Panel.bluetoothView does.
      full.view = signalsTick(full.view, {
        "CC:1": 1,
        "CC:2": 3
      })
      t.step(50, function () {
        var availableRowsAfter = t.findChildren(available, "deviceRow")
        t.equal(availableRowsAfter.length, availableRows.length, "a signals tick keeps the row count")
        for (var i = 0; i < availableRows.length; i++)
          t.check(availableRowsAfter[i] === availableRows[i], "available row " + i + " is the same delegate after a signals tick")
        t.equal(availableRowsAfter[0].signal, 1, "the updated signal level reaches its row")
        t.equal(availableRowsAfter[1].signal, 3, "the other updated signal level reaches its row")

        // The cursor outline is the keyboard's alone.
        full.view = cursorTick(full.view, false, "connected", 0, false)
        t.step(50, function () {
          t.equal(litOutlines(full), 0, "no outline without an active cursor")
          full.view = cursorTick(full.view, true, "known", 1, false)
          t.step(50, function () {
            t.equal(litOutlines(full), 1, "an active cursor outlines exactly one row")

            // Every trailing element ends on one right content edge.
            var header = t.findChild(full, "bluetoothHeader")
            t.check(header !== null && header.hintTip.text === "Turn Bluetooth off", "the power switch explains itself (stock's toggleHint)")
            var edge = rightEdge(full)
            var trailing = [t.findChild(full, "headerTrailing"), connectedRows[0], pairedRows[0], availableRows[0]]
            for (var j = 0; j < trailing.length; j++)
              t.check(Math.abs(rightEdge(trailing[j]) - edge) < 0.5, "trailing element " + j + " ends on the content edge")

            // No adapter: the empty text shows and the lists are hidden.
            t.check(!t.findChild(bare, "connectedSection").visible, "no adapter hides Connected")
            t.check(!t.findChild(bare, "pairedSection").visible, "no adapter hides Paired")
            t.check(!t.findChild(bare, "availableSection").visible, "no adapter hides Available")
            var emptyText = t.findChild(bare, "emptyText")
            t.check(emptyText !== null && emptyText.visible && emptyText.text === "No Bluetooth adapter", "no adapter shows the empty text")
            t.check(!t.findChild(full, "emptyText").visible, "a working adapter with devices shows no empty text")

            t.done()
          })
        })
      })
    })
  })
}
