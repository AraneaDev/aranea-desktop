// The Aranea Bluetooth view, driven by a plain view object: Connected,
// Paired and Available sections show and hide with the fixture lists, an
// adapter that is off keeps Paired (as stock does) but never shows
// Available, the scanning pulse runs only while open, scanning and on,
// device glyphs and busy pulses come from the fixture, forget shows only
// for forgettable rows and never steals width from the detail text while
// hidden, hovering forget swaps its row's tooltip for its own and reports
// a dedicated hover action, available rows emit primary and right-click
// emits secondary, the signal glow follows the separate signals map
// without rebuilding rows, the keyboard cursor outlines exactly one row
// when active, Paired/Available scroll together under a pinned Connected
// and ensureVisible scrolls a row (and a first row's caption) into view,
// every trailing element ends on one right content edge, the key hint
// fits one line, and a missing adapter hides the lists behind the empty
// text. The header caption's opacity follows captionOpacity. Every device
// row carries the dropdown's PointerMoveGate, and a device that slides
// under a still pointer (a list change, not a real move) never steals the
// keyboard cursor via a synthetic hover action.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.bluetooth" as Bluetooth
import "plugins/araneadev.shared" as Aranea

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
        open: true,
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

  // A present adapter, turned off, as Panel.bluetoothView builds it: no
  // connected devices, the paired ones still listed (stock shows them, and
  // choosing one powers the adapter on and connects), no scan and no
  // empty text.
  Bluetooth.BluetoothDropdown {
    id: off
    width: 360
    view: ({
        glyph: String.fromCodePoint(0xf00b2),
        caption: "Turned Off",
        enabled: false,
        hasAdapter: true,
        open: true,
        toggleHint: "Turn Bluetooth on",
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
            key: "ZZ:2",
            label: "MX Master 3S",
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
  }

  // Many paired devices and a small scroll cap, for ensureVisible.
  Bluetooth.BluetoothDropdown {
    id: scroller
    width: 360
    maxScrollHeight: 60
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
        known: Array.from({
          length: 10
        }, function (_, i) {
          return {
            key: "K:" + i,
            label: "Device " + i,
            glyph: "",
            detail: "",
            busy: false,
            forgettable: false
          }
        }),
        discovered: [],
        signals: {},
        emptyText: ""
      })
  }

  // Actions reported by gated's action signal, in emission order.
  property var gatedActions: []

  // Three known devices, so removing the first slides the others up one
  // row under a pointer that never moved.
  function gatedView(known) {
    return {
      glyph: "",
      caption: "",
      enabled: true,
      hasAdapter: true,
      toggleHint: "",
      headerCursor: false,
      open: true,
      scanning: false,
      cursor: {
        active: false,
        section: "known",
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

  // Real window + real pointer moves, so Qt's hover delivery (including the
  // synthetic re-hover a shifting delegate gets under a still pointer) is
  // genuine rather than simulated through direct signal calls.
  FloatingWindow {
    id: gateWindow
    implicitWidth: 380
    implicitHeight: 300
    visible: true

    Bluetooth.BluetoothDropdown {
      id: gated
      width: 360
      view: gatedView([
        {
          key: "AA:1",
          label: "Device A",
          glyph: "",
          detail: "",
          busy: false,
          forgettable: true
        },
        {
          key: "AA:2",
          label: "Device B",
          glyph: "",
          detail: "",
          busy: false,
          forgettable: true
        },
        {
          key: "AA:3",
          label: "Device C",
          glyph: "",
          detail: "",
          busy: false,
          forgettable: true
        }
      ])
      onAction: function (name, arg) {
        gatedActions.push([name, arg])
      }
    }
  }

  // Synthesizes the pointer events (TestCase's mouseMove), never run as a test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // VIEW with only signals replaced by SIGNALS; every row array is reused.
  function signalsTick(view, signals) {
    var next = {}
    for (var key in view)
      next[key] = view[key]
    next.signals = signals
    return next
  }

  // VIEW with FIELDS (a plain object) laid over it; other values reused.
  function withFields(view, fields) {
    var next = {}
    for (var key in view)
      next[key] = view[key]
    for (var f in fields)
      next[f] = fields[f]
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

  // Right edge of ITEM in HOST's coordinates.
  function rightEdge(item, host) {
    return item.mapToItem(host, item.width, 0).x
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
    var offView = off.view
    off.view = withFields(offView, {
      scanning: true,
      discovered: [
        {
          key: "ZZ:3",
          label: "Stale",
          glyph: "",
          detail: "",
          busy: false,
          forgettable: false
        }
      ]
    })
    t.check(!t.findChild(off, "scanPulse").visible, "the pulse stays hidden with the adapter off, even if scanning is reported")
    t.check(!t.findChild(off, "availableSection").visible, "adapter off hides Available, even if scanning is reported")
    off.view = offView
    var fullView = full.view
    full.view = withFields(fullView, {
      open: false
    })
    t.check(!t.findChild(full, "scanPulse").visible, "the pulse stops while the dropdown is closed")
    full.view = fullView
    t.check(t.findChild(full, "scanPulse").visible, "the pulse runs again once the dropdown is open")
    var hint = t.findChild(full, "keyHint")
    t.check(hint !== null && hint.text.indexOf("b power") !== -1, "the key hint names b power")
    t.check(hint !== null && !hint.truncated && hint.lineCount === 1, "the key hint fits on one line")

    // Busy rows (Keychron K3, index 2 in Paired) run their breathing pulse.
    var busyPulse = t.findChildren(pairedRows[2], "busyPulse")[0]
    var idlePulse = t.findChildren(pairedRows[0], "busyPulse")[0]
    t.check(busyPulse !== undefined && busyPulse.running, "a busy row runs its pulse")
    t.check(idlePulse !== undefined && !idlePulse.running, "an idle row's pulse does not run")

    // Forget is hidden off cursor for every row, forgettable or not, and a
    // hidden forget button must not push the detail text off the row's own
    // right edge (it reserves zero width while invisible).
    var connectedForget = t.findChildren(connected, "forgetButton")
    var availableForget = t.findChildren(available, "forgetButton")
    t.check(!connectedForget[0].visible, "forget hides off cursor even on a forgettable row")
    t.check(!availableForget[0].visible, "available rows are never forgettable")
    var pairedDetail0 = t.findChild(pairedRows[0], "detailText")
    var availableDetail0 = t.findChild(availableRows[0], "detailText")
    var detailMargin = Style.space(8)
    t.check(Math.abs(rightEdge(pairedDetail0, pairedRows[0]) - (pairedRows[0].width - detailMargin)) < 0.5, "a hidden forget button doesn't push the paired row's detail text left")
    t.check(Math.abs(rightEdge(availableDetail0, availableRows[0]) - (availableRows[0].width - detailMargin)) < 0.5, "an available row's detail text reaches its own row edge (forget never shows there)")

    full.view = cursorTick(full.view, true, "connected", 0, false)
    t.step(50, function () {
      var connectedForgetOnCursor = t.findChildren(connected, "forgetButton")
      t.check(connectedForgetOnCursor[0].visible, "forget shows once the cursor sits on a forgettable row")
      t.check(connectedForgetOnCursor[0].width > 0, "a shown forget button has real width")
      var connectedBorder = t.findChild(connectedForgetOnCursor[0], "forgetBorder")
      var connectedLabel = t.findChild(connectedForgetOnCursor[0], "forgetLabel")
      t.check(connectedLabel.text.indexOf("forget") !== -1, "the forget button reads \"forget\"")
      t.check(connectedBorder.border.color !== Aranea.DesignTokens.urgent, "forget is muted, not bright, with the cursor on the row but not its action")
      full.view = cursorTick(full.view, true, "connected", 0, true)
      t.step(50, function () {
        t.equal(connectedBorder.border.color, Aranea.DesignTokens.urgent, "forget brightens to full urgent once the cursor's action is on it")
        t.equal(connectedLabel.color, Aranea.DesignTokens.urgent, "the label brightens with it")
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

        // Hovering the forget button reports a dedicated hover action with
        // action: true, and action: false plus leave: true once it leaves
        // (still over the row), via the section's own signal (there's no real pointer in
        // this offscreen harness to synthesize a true hover with).
        paired.actionHovered(2, true)
        t.equal(JSON.stringify(actions[actions.length - 1]), JSON.stringify(["hover",
          {
            section: "known",
            index: 2,
            action: true
          }
        ]), "hovering forget reports action: true")
        paired.actionHovered(2, false)
        t.equal(JSON.stringify(actions[actions.length - 1]), JSON.stringify(["hover",
          {
            section: "known",
            index: 2,
            action: false,
            leave: true
          }
        ]), "leaving forget (still on the row) reports action: false with leave: true")

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

              // Every trailing element ends on one right content edge: the
              // header's switch slot, and a visible forget button (a bare
              // device row is trivially anchored full-width and proves
              // nothing on its own).
              var header = t.findChild(full, "bluetoothHeader")
              t.check(header !== null && header.hintTip.text === "Turn Bluetooth off", "the power switch explains itself (stock's toggleHint)")
              // The caption fades with captionOpacity, apart from the view.
              var caption = t.findChild(header, "headerCaption")
              t.check(caption !== null && caption.opacity === 1, "the caption starts fully opaque")
              full.captionOpacity = 0.25
              t.check(caption !== null && Math.abs(caption.opacity - 0.25) < 0.001, "the caption opacity follows captionOpacity")
              t.check(caption !== null && caption.text === "HERDING HEADSETS", "fading the caption keeps its text")
              full.captionOpacity = 1
              var edge = rightEdge(full, full)
              var cursorForget = t.findChildren(paired, "forgetButton").filter(function (b) {
                return b.visible
              })[0]
              var trailing = [t.findChild(full, "headerTrailing"), cursorForget]
              for (var j = 0; j < trailing.length; j++)
                t.check(Math.abs(rightEdge(trailing[j], full) - edge) < 0.5, "trailing element " + j + " ends on the content edge")

              // Paired/Available scroll together under a pinned Connected.
              var scroll = t.findChild(full, "deviceScroll")
              t.check(scroll !== null, "the scroll area exists")
              t.check(t.findChild(scroll, "pairedSection") !== null && t.findChild(scroll, "availableSection") !== null, "Paired and Available live inside the scroll area")
              t.check(t.findChild(full, "connectedSection") !== null, "Connected is pinned outside the scroll area")

              // No adapter: the empty text shows and the lists are hidden.
              t.check(!t.findChild(bare, "connectedSection").visible, "no adapter hides Connected")
              t.check(!t.findChild(bare, "pairedSection").visible, "no adapter hides Paired")
              t.check(!t.findChild(bare, "availableSection").visible, "no adapter hides Available")
              var emptyText = t.findChild(bare, "emptyText")
              t.check(emptyText !== null && emptyText.visible && emptyText.text === "No Bluetooth adapter", "no adapter shows the empty text")
              t.check(!t.findChild(full, "emptyText").visible, "a working adapter with devices shows no empty text")

              // A present-but-off adapter keeps Paired, as stock does.
              t.check(t.findChild(off, "pairedSection").visible, "adapter off still shows Paired")
              t.equal(t.findChildren(t.findChild(off, "pairedSection"), "deviceRow").length, 1, "adapter off lists the paired device")
              t.check(!t.findChild(off, "availableSection").visible, "adapter off shows no Available")
              t.check(!t.findChild(off, "emptyText").visible, "adapter off with paired devices shows no empty text")

              // ensureVisible scrolls a row below the fold into view.
              t.step(50, function () {
                var scrollerFlick = t.findChild(scroller, "deviceScroll")
                t.equal(scrollerFlick.contentY, 0, "the scroll area starts at the top")
                scroller.ensureVisible("known", 9)
                t.step(50, function () {
                  t.check(scrollerFlick.contentY > 0, "ensureVisible scrolls a row below the fold into view")
                  scroller.ensureVisible("known", 0)
                  t.step(50, function () {
                    var pairedCaption = t.findChild(scroller, "pairedSection")
                    var captionTop = pairedCaption.mapToItem(scrollerFlick.contentItem, 0, 0).y
                    t.check(scrollerFlick.contentY <= captionTop, "ensureVisible on a section's first row shows its caption too")

                    var gatedRows = t.findChildren(gated, "deviceRow")
                    t.equal(gatedRows.length, 3, "the gated fixture lists all three devices")
                    for (var gi = 0; gi < gatedRows.length; gi++)
                      t.check(gatedRows[gi].pointerGate !== null, "device row " + gi + " carries the dropdown's pointer gate")

                    var pt = gatedRows[1].mapToItem(gated, 10, gatedRows[1].height / 2)
                    pointer.mouseMove(gated, pt.x, pt.y)
                    t.step(80, function () {
                      pointer.mouseMove(gated, pt.x + 4, pt.y)
                      t.step(80, function () {
                        t.check(gatedActions.some(function (a) {
                          return a[0] === "hover" && a[1].section === "known" && a[1].index === 1
                        }), "a real hover on row 1 reports a hover action")
                        gatedActions = []
                        // Remove the first device without moving the pointer:
                        // the device now under it (was row 2) slides up to
                        // take row 1's place, exactly a row moving under a
                        // still pointer.
                        gated.view = gatedView([
                          {
                            key: "AA:2",
                            label: "Device B",
                            glyph: "",
                            detail: "",
                            busy: false,
                            forgettable: true
                          },
                          {
                            key: "AA:3",
                            label: "Device C",
                            glyph: "",
                            detail: "",
                            busy: false,
                            forgettable: true
                          }
                        ])
                        t.step(80, function () {
                          t.equal(gatedActions.length, 0, "a device sliding under a still pointer emits no hover action")
                          pointer.mouseMove(gated, pt.x, pt.y + 5)
                          t.step(80, function () {
                            t.check(gatedActions.length > 0, "a real move after the slide reports hover again")
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
