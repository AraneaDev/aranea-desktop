// The assembled Aranea Network dropdown, driven by a plain view object in
// a real window with real pointer clicks and key presses: every section
// shows and hides on its fixture data (and the empty text takes over when
// there's no Wi-Fi at all); the Wi-Fi list draws its section titles, a
// lock on secured rows, "Hidden" for a nameless network, status text (the
// failure urgent, busy rows breathing) and a forget button only on
// forgettable rows under the cursor, which emits wifiForget while a row
// click emits wifiPrimary; the passphrase prompt opens under its row with
// the passphrase focused (identity first for enterprise), typing emits
// passphraseEdited/identityEdited, Enter submits, Esc cancels, the connect
// button submits and busy or failed swap the fields for stock's messages;
// Saved rows are dimmed, never chosen, and their forget emits savedForget;
// changing stats, graph, wifiStatus, captionOpacity or prompt keeps the
// same Wi-Fi row delegates and a half-typed passphrase; an inactive cursor
// draws no outline and an active one draws exactly one in every section;
// every trailing element ends on one right content edge; ensureVisible
// scrolls the Wi-Fi area; and a row sliding under a still pointer emits no
// hover.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.network" as Network
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  QmlTest {
    id: t
  }

  // Actions reported by full, as [name, arg], in emission order.
  property var actions: []

  // Synthesizes pointer and key events (TestCase's mouse and key helpers),
  // never run as a test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // The Wi-Fi rows, built once so a view rebuilt with the same rows keeps
  // the same model (as Panel's networkView does).
  readonly property var wifiRows: [
    {
      key: "Interwebz24Ghz",
      label: "Interwebz24Ghz",
      glyph: String.fromCodePoint(0xf0928),
      title: "KNOWN NETWORKS",
      secured: true,
      known: true,
      connected: true,
      forgettable: true,
      enterprise: false
    },
    {
      key: "HomeOpen",
      label: "HomeOpen",
      glyph: String.fromCodePoint(0xf0925),
      title: "",
      secured: false,
      known: true,
      connected: false,
      forgettable: true,
      enterprise: false
    },
    {
      key: "Ziggo-5G",
      label: "Ziggo-5G",
      glyph: String.fromCodePoint(0xf0922),
      title: "OTHER NETWORKS",
      secured: true,
      known: false,
      connected: false,
      forgettable: false,
      enterprise: false
    },
    {
      key: "CorpEAP",
      label: "CorpEAP",
      glyph: String.fromCodePoint(0xf0922),
      title: "",
      secured: true,
      known: false,
      connected: false,
      forgettable: false,
      enterprise: true
    },
    {
      key: "",
      label: "",
      glyph: String.fromCodePoint(0xf091f),
      title: "",
      secured: false,
      known: false,
      connected: false,
      forgettable: false,
      enterprise: false
    }
  ]

  // A full view with every section populated, CURSOR its cursor and ROWS
  // its Wi-Fi rows.
  function fullView(cursor, rows) {
    return {
      header: {
        glyph: String.fromCodePoint(0xf05a9),
        title: "Interwebz24Ghz (2.4 GHz)",
        caption: "Wiring bits",
        canQr: true,
        canSpeed: true,
        canToggle: true,
        wifiOn: true,
        toggleHint: "Turn Wi-Fi off",
        scanning: false
      },
      interfaces: [
        {
          key: "wlp2s0",
          glyph: String.fromCodePoint(0xf05a9),
          label: "wlp2s0",
          detail: "Wi-Fi · connected · 192.168.0.126",
          active: true
        },
        {
          key: "enp3s0",
          glyph: String.fromCodePoint(0xf0200),
          label: "enp3s0",
          detail: "Ethernet · cable unplugged",
          active: false
        }
      ],
      vpn: [
        {
          key: "uuid-wg",
          glyph: String.fromCodePoint(0xf0582),
          label: "office-wg",
          detail: "WireGuard · 10.8.0.3",
          active: true
        }
      ],
      band: {
        visible: true,
        title: "BAND · 2.4 GHz",
        auto: false,
        currentLabel: "2.4 GHz",
        pillsVisible: true,
        busy: false,
        options: [
          {
            key: "2.4",
            label: "2.4 GHz",
            tooltip: "Pin 2.4 GHz",
            selected: true
          },
          {
            key: "5",
            label: "5 GHz",
            tooltip: "Pin 5 GHz",
            selected: false
          },
          {
            key: "6",
            label: "6 GHz",
            tooltip: "Pin 6 GHz",
            selected: false
          }
        ]
      },
      dns: {
        options: [
          {
            key: "DHCP",
            label: "DHCP",
            selected: true,
            tooltip: ""
          },
          {
            key: "Cloudflare",
            label: "Cloudflare",
            selected: false,
            tooltip: "Set DNS to Cloudflare"
          },
          {
            key: "Google",
            label: "Google",
            selected: false,
            tooltip: "Set DNS to Google"
          },
          {
            key: "Custom",
            label: "Custom",
            selected: false,
            tooltip: "Set custom DNS servers"
          }
        ]
      },
      wifi: {
        available: true,
        scanning: true,
        rows: rows
      },
      saved: [
        {
          key: "uuid-guest",
          label: "Office-Guest",
          detail: "last used 3 days ago"
        },
        {
          key: "uuid-grandma",
          label: "Grandma-WiFi",
          detail: "never used"
        }
      ],
      cursor: cursor,
      emptyText: ""
    }
  }

  // A cursor object: ACTIVE on SECTION's INDEX, on its action when ACTION,
  // on the band's Automatic switch when BANDAUTO.
  function cur(active, section, index, action, bandAuto) {
    return {
      active: active,
      section: section,
      index: index,
      action: !!action,
      bandAuto: !!bandAuto
    }
  }

  // The view, keeping its rows, with the cursor moved.
  function withCursor(c) {
    return fullView(c, wifiRows)
  }

  // A closed prompt.
  readonly property var closedPrompt: ({
      ssid: "",
      enterprise: false,
      busy: false,
      failed: false,
      passphrase: "",
      identity: ""
    })

  // The open prompt for SSID with FIELDS merged in.
  function promptFor(ssid, fields) {
    var p = {
      ssid: ssid,
      enterprise: false,
      busy: false,
      failed: false,
      passphrase: "",
      identity: ""
    }
    for (var k in fields)
      p[k] = fields[k]
    return p
  }

  // The last action as JSON.
  function last() {
    return actions.length ? JSON.stringify(actions[actions.length - 1]) : ""
  }

  // Whether an action NAME with ARG (compared as JSON) was reported.
  function reported(name, arg) {
    var want = JSON.stringify([name, arg])
    return actions.some(function (a) {
      return JSON.stringify(a) === want
    })
  }

  // Actions other than hover.
  function nonHover() {
    return actions.filter(function (a) {
      return a[0] !== "hover"
    })
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

  // The visible items named NAME under ROOT.
  function shown(root, name) {
    return t.findChildren(root, name).filter(function (i) {
      return i.visible
    })
  }

  // Runs STEPS ([delay, fn] pairs) one after another, then ends the run.
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
    id: win
    implicitWidth: 400
    implicitHeight: 2400
    visible: true

    Column {
      x: 20
      width: 360
      spacing: 20

      Network.NetworkDropdown {
        id: full
        width: 360
        maxScrollHeight: 2000
        view: fullView(cur(false, "wifi", 0), wifiRows)
        stats: ({
            visible: true,
            receiving: "3.4 MB/s",
            sending: "120 KB/s",
            ping: "14 ms",
            loss: "0%",
            lossy: false,
            downloaded: "1.8 GB",
            uploaded: "210 MB",
            ip: "192.168.0.126",
            gateway: "192.168.0.1"
          })
        graph: [
          {
            rx: 1000,
            tx: 10
          }
        ]
        wifiStatus: ({
            "HomeOpen": {
              text: "Couldn't connect",
              failed: true,
              busy: false
            },
            "Ziggo-5G": {
              text: "Connecting…",
              failed: false,
              busy: true
            }
          })
        vpnStatus: ({})
        prompt: closedPrompt
        onAction: function (name, arg) {
          actions.push([name, arg])
          // Echo edits back the way Panel does, so the field's binding
          // to prompt.passphrase/identity sees what was typed.
          if (name === "passphraseEdited")
            full.prompt = promptFor(full.prompt.ssid, {
              enterprise: full.prompt.enterprise,
              passphrase: arg.text,
              identity: full.prompt.identity
            })
          else if (name === "identityEdited")
            full.prompt = promptFor(full.prompt.ssid, {
              enterprise: full.prompt.enterprise,
              passphrase: full.prompt.passphrase,
              identity: arg.text
            })
        }
      }

      // Nothing but a header: Wi-Fi off, no VPN, no band, one interface.
      Network.NetworkDropdown {
        id: bare
        width: 360
        view: ({
            header: {
              glyph: "",
              title: "Ethernet",
              caption: "Not connected",
              canQr: false,
              canSpeed: false,
              canToggle: true,
              wifiOn: false,
              toggleHint: "Turn Wi-Fi on",
              scanning: false
            },
            interfaces: [
              {
                key: "enp3s0",
                glyph: "",
                label: "enp3s0",
                detail: "Ethernet",
                active: false
              }
            ],
            vpn: [],
            band: {
              visible: false
            },
            dns: {
              options: []
            },
            wifi: {
              available: false,
              scanning: false,
              rows: []
            },
            saved: [],
            cursor: {
              active: false,
              section: "",
              index: -1,
              action: false,
              bandAuto: false
            },
            emptyText: "Wi-Fi is off"
          })
        stats: ({
            visible: false
          })
      }

      // A short scroll area for ensureVisible.
      Network.NetworkDropdown {
        id: scroller
        width: 360
        maxScrollHeight: 80
        view: fullView(cur(false, "wifi", 0), wifiRows)
      }
    }
  }

  Component.onCompleted: run([[300, function () {
        // ---------- Sections show and hide ----------
        var names = ["networkHeader", "linkSection", "interfacesSection", "vpnSection", "bandSection", "dnsSection", "wifiSection", "savedSection"]
        for (var i = 0; i < names.length; i++) {
          var s = t.findChild(full, names[i])
          t.check(s !== null && s.visible, names[i] + " shows with its data")
        }
        var hidden = ["linkSection", "interfacesSection", "vpnSection", "bandSection", "wifiSection", "savedSection"]
        for (var j = 0; j < hidden.length; j++)
          t.check(!t.findChild(bare, hidden[j]).visible, hidden[j] + " hides without its data")
        t.check(t.findChild(bare, "networkHeader").visible, "the header always shows")
        t.equal(shown(full, "separator").length, 7, "a separator above every shown section")
        t.equal(shown(bare, "separator").length, 0, "no separator without sections")
        var empty = t.findChild(bare, "emptyText")
        t.check(empty.visible && empty.text === "Wi-Fi is off", "no Wi-Fi at all shows the empty text")
        t.check(!t.findChild(full, "emptyText").visible, "Wi-Fi rows hide the empty text")
        t.equal(t.findChild(full, "keyHint").text, "↑↓ move · ←→ pick · enter connect · x forget · tab next", "the key hint")
        t.check(t.findChild(full, "scanningCaption").visible, "scanning shows SCANNING WI-FI…")
        t.equal(t.findChild(full, "scanningCaption").text, "SCANNING WI-FI…", "the scanning caption's text")
        var scroll = t.findChild(full, "wifiScroll")
        t.check(scroll !== null && t.findChild(scroll, "wifiSection") !== null && t.findChild(scroll, "savedSection") !== null, "Wi-Fi and Saved live in the scroll area")
        t.check(t.findChild(scroll, "dnsSection") === null, "DNS is pinned outside it")

        // ---------- Wi-Fi rows ----------
        var wifi = t.findChild(full, "wifiSection")
        t.equal(shown(wifi, "wifiTitle").map(function (x) {
          return x.text
        }), ["KNOWN NETWORKS", "OTHER NETWORKS"], "section titles show where the rows say")
        var rows = t.findChildren(wifi, "wifiRow")
        t.equal(rows.length, 5, "five Wi-Fi rows")
        t.equal(rows.map(function (r) {
          return r.label
        }), ["Interwebz24Ghz", "HomeOpen", "Ziggo-5G", "CorpEAP", "Hidden"], "labels, Hidden for a nameless network")
        t.equal(rows.map(function (r) {
          return t.findChild(r, "wifiLock").visible
        }), [true, false, true, true, false], "a lock on secured rows only")
        t.check(rows[0].active && !rows[1].active, "the connected row is lit")
        t.equal(rows[0].signal, -1, "the glyph carries strength, not the node")
        t.equal(rows[1].detail, "Couldn't connect", "status text is the detail")
        t.equal(t.findChild(rows[1], "detailText").color, Aranea.DesignTokens.urgent, "a failure is urgent")
        t.check(rows[2].busy && !rows[1].busy, "a busy row breathes")
        t.equal(rows[2].detail, "Connecting…", "busy status text")
        t.equal(shown(wifi, "forgetButton").length, 0, "no forget without hover or cursor")

        // ---------- Saved rows ----------
        var saved = t.findChild(full, "savedSection")
        t.equal(t.findChild(saved, "savedCaption").text, "SAVED, OUT OF RANGE", "the Saved caption")
        t.equal(t.findChild(saved, "savedCount").text, "2", "the Saved count")
        var savedRows = t.findChildren(saved, "savedRow")
        t.equal(savedRows.length, 2, "two saved rows")
        t.check(Math.abs(savedRows[0].opacity - 0.7) < 0.001, "saved rows are dimmed")
        t.equal(savedRows[0].glyph, String.fromCodePoint(0xf092e), "saved rows carry the Wi-Fi-off glyph")
        t.equal(savedRows[0].detail, "last used 3 days ago", "saved rows show their detail")
        t.equal(shown(saved, "forgetButton").length, 0, "no saved forget without hover or cursor")

        // ---------- No outline without the cursor ----------
        t.equal(litOutlines(full), 0, "an inactive cursor draws no outline")

        // Row click.
        actions = []
        pointer.mouseClick(rows[2], 40, rows[2].height / 2)
        t.check(reported("wifiPrimary", {
          index: 2
        }), "a row click emits wifiPrimary")
        actions = []
        // Move first, as a real pointer does, so hover tracking (and
        // leaving below) sees it.
        pointer.mouseMove(savedRows[1], 40, savedRows[1].height / 2)
        pointer.mouseClick(savedRows[1], 40, savedRows[1].height / 2)
        t.equal(nonHover().length, 0, "a saved row click emits nothing")

        // Park the pointer off the rows, so only the cursor shows forget.
        pointer.mouseMove(t.findChild(full, "keyHint"), 4, 4)
        // Cursor on a forgettable row shows forget.
        full.view = withCursor(cur(true, "wifi", 0, false))
      }], [60, function () {
        var wifi = t.findChild(full, "wifiSection")
        var rows = t.findChildren(wifi, "wifiRow")
        var forgets = shown(wifi, "forgetButton")
        t.equal(forgets.length, 1, "the cursor shows forget on its forgettable row")
        t.check(!t.findChild(rows[0], "wifiLock").visible, "forget takes the lock's place")
        t.equal(t.findChild(forgets[0], "forgetTip").text, "Forget network", "forget explains itself")
        actions = []
        pointer.mouseClick(forgets[0])
        t.check(reported("wifiForget", {
          index: 0
        }), "forget emits wifiForget")
        full.view = withCursor(cur(true, "wifi", 2, false))
      }], [60, function () {
        t.equal(shown(t.findChild(full, "wifiSection"), "forgetButton").length, 0, "no forget on a row that can't be forgotten")
        full.view = withCursor(cur(true, "saved", 0, true))
      }], [60, function () {
        var saved = t.findChild(full, "savedSection")
        var forgets = shown(saved, "forgetButton")
        t.equal(forgets.length, 1, "the cursor shows a saved forget")
        t.check(forgets[0].bright, "the cursor's action tints it")
        actions = []
        pointer.mouseClick(forgets[0])
        t.check(reported("savedForget", {
          index: 0
        }), "saved forget emits savedForget")

        // ---------- One outline per section ----------
        var cases = [cur(true, "header", 1), cur(true, "vpn", 0), cur(true, "band", 0, false, true), cur(true, "band", 2, false, false), cur(true, "dns", 1), cur(true, "wifi", 3), cur(true, "saved", 1)]
        for (var i = 0; i < cases.length; i++) {
          full.view = withCursor(cases[i])
          t.equal(litOutlines(full), 1, "an active cursor on " + cases[i].section + (cases[i].section === "band" ? (cases[i].bandAuto ? " auto" : " pill") : "") + " draws exactly one outline")
        }
        full.view = withCursor(cur(true, "wifi", 1))
      }], [60, function () {
        // ---------- One right content edge ----------
        var edge = rightEdge(full, full)
        var wifi = t.findChild(full, "wifiSection")
        var rows = t.findChildren(wifi, "wifiRow")
        var bandPills = t.findChildren(t.findChild(full, "bandSection"), "pill")
        var dnsPills = t.findChildren(t.findChild(full, "dnsSection"), "pill")
        var trailing = [["header", t.findChild(full, "headerTrailing")], ["VPN switch", t.findChild(full, "vpnSwitch")], ["Automatic", t.findChild(full, "autoSwitch")], ["last band pill", bandPills[bandPills.length - 1]], ["last DNS pill", dnsPills[dnsPills.length - 1]], ["Wi-Fi forget", shown(wifi, "forgetButton")[0]], ["Wi-Fi lock", t.findChild(rows[2], "wifiLock")]]
        for (var j = 0; j < trailing.length; j++)
          t.check(trailing[j][1] && Math.abs(rightEdge(trailing[j][1], full) - edge) < 0.5, trailing[j][0] + " ends on the content edge")
        full.view = withCursor(cur(true, "saved", 1))
      }], [60, function () {
        var forget = shown(t.findChild(full, "savedSection"), "forgetButton")[0]
        t.check(forget && Math.abs(rightEdge(forget, full) - rightEdge(full, full)) < 0.5, "saved forget ends on the content edge")

        // ---------- The passphrase prompt ----------
        full.view = withCursor(cur(false, "wifi", 2))
        actions = []
        full.prompt = promptFor("Ziggo-5G", {})
      }], [150, function () {
        var wifi = t.findChild(full, "wifiSection")
        var panels = shown(wifi, "promptPanel")
        t.equal(panels.length, 1, "the prompt opens under one row")
        var wrappers = t.findChildren(wifi, "wifiRowWrapper")
        t.check(t.findChild(wrappers[2], "promptPanel").visible, "under the row whose key it names")
        t.check(Math.abs(rightEdge(panels[0], full) - rightEdge(full, full)) < 0.5, "the prompt ends on the content edge")
        var pw = t.findChild(wrappers[2], "passphraseField")
        t.check(pw.visible && pw.activeFocus, "opening the prompt focuses the passphrase")
        t.check(!t.findChild(wrappers[2], "identityField").visible, "no identity field for a personal network")
        t.equal(pw.placeholderText, "Passphrase", "the passphrase placeholder")
        t.equal(pw.echoMode, TextInput.Password, "the passphrase is echoed as a password")
        var btn = t.findChild(wrappers[2], "connectButton")
        t.equal(btn.tooltipText, "Connect", "the connect button explains itself")
        pointer.keyClick(Qt.Key_A)
        pointer.keyClick(Qt.Key_B)
      }], [60, function () {
        var wrappers = t.findChildren(t.findChild(full, "wifiSection"), "wifiRowWrapper")
        var pw = t.findChild(wrappers[2], "passphraseField")
        t.equal(pw.text, "ab", "typing reaches the passphrase field")
        t.check(reported("passphraseEdited", {
          text: "a"
        }) && reported("passphraseEdited", {
          text: "ab"
        }), "typing emits passphraseEdited")

        // ---------- Identity across refreshes ----------
        identityBefore = t.findChildren(t.findChild(full, "wifiSection"), "wifiRowWrapper").concat(t.findChildren(t.findChild(full, "wifiSection"), "wifiRow"))
        // A selection only the same field instance can keep.
        pw.select(0, 1)
        full.stats = {
          visible: true,
          receiving: "1 KB/s",
          sending: "1 KB/s",
          ping: "20 ms",
          loss: "0%",
          lossy: false,
          downloaded: "1.9 GB",
          uploaded: "211 MB",
          ip: "192.168.0.126",
          gateway: "192.168.0.1"
        }
        full.graph = [
          {
            rx: 1000,
            tx: 10
          },
          {
            rx: 2000,
            tx: 20
          }
        ]
        full.wifiStatus = {
          "HomeOpen": {
            text: "",
            failed: false,
            busy: false
          }
        }
        full.captionOpacity = 0.4
        full.vpnStatus = {
          "uuid-wg": {
            busy: true,
            failed: false
          }
        }
        full.prompt = promptFor("Ziggo-5G", {
          passphrase: "ab"
        })
      }], [100, function () {
        var after = t.findChildren(t.findChild(full, "wifiSection"), "wifiRowWrapper")
        var now = after.concat(t.findChildren(t.findChild(full, "wifiSection"), "wifiRow"))
        t.check(now.length === 10 && identityBefore.length === 10 && identityBefore.every(function (w, k) {
          return w === now[k]
        }), "fast properties keep the same Wi-Fi row delegates")
        var pwAfter = t.findChild(after[2], "passphraseField")
        t.equal(pwAfter.text, "ab", "a half-typed passphrase survives the refresh")
        t.equal(pwAfter.selectedText, "a", "in the same field (its selection kept)")
        t.check(pwAfter.activeFocus, "and keeps its focus")
        full.captionOpacity = 1
        pwAfter.deselect()

        actions = []
        pointer.keyClick(Qt.Key_Return)
        t.check(reported("promptSubmit", null), "Enter in the passphrase emits promptSubmit")
        actions = []
        pointer.mouseClick(t.findChild(after[2], "connectButton"))
        t.check(reported("promptSubmit", null), "the connect button emits promptSubmit")
        t.findChild(after[2], "passphraseField").forceActiveFocus()
        actions = []
        pointer.keyClick(Qt.Key_Escape)
        t.check(reported("promptCancel", null), "Esc emits promptCancel")

        full.prompt = promptFor("Ziggo-5G", {
          passphrase: "ab",
          busy: true
        })
      }], [60, function () {
        var w = t.findChildren(t.findChild(full, "wifiSection"), "wifiRowWrapper")[2]
        var status = t.findChild(w, "promptStatus")
        t.check(status.visible && status.text === "Connecting...", "busy shows Connecting...")
        t.check(!t.findChild(w, "passphraseField").visible && !t.findChild(w, "connectButton").visible, "busy hides the field and button")
        full.prompt = promptFor("Ziggo-5G", {
          passphrase: "ab",
          failed: true
        })
        t.check(status.visible && status.text === "Wrong password", "failed shows Wrong password")
        t.equal(status.color, Aranea.DesignTokens.urgent, "Wrong password is urgent")

        // Enterprise: identity first.
        full.prompt = closedPrompt
      }], [60, function () {
        t.equal(shown(t.findChild(full, "wifiSection"), "promptPanel").length, 0, "a closed prompt shows nowhere")
        actions = []
        full.prompt = promptFor("CorpEAP", {
          enterprise: true
        })
      }], [150, function () {
        var w = t.findChildren(t.findChild(full, "wifiSection"), "wifiRowWrapper")[3]
        var id = t.findChild(w, "identityField")
        t.check(id.visible && id.activeFocus, "enterprise focuses the identity field first")
        t.equal(id.placeholderText, "Identity (user@domain)", "the identity placeholder")
        t.check(id.y < t.findChild(w, "passphraseField").mapToItem(id.parent, 0, 0).y, "identity sits above the passphrase")
        pointer.keyClick(Qt.Key_U)
      }], [60, function () {
        var w = t.findChildren(t.findChild(full, "wifiSection"), "wifiRowWrapper")[3]
        t.check(reported("identityEdited", {
          text: "u"
        }), "typing emits identityEdited")
        pointer.keyClick(Qt.Key_Return)
      }], [60, function () {
        var w = t.findChildren(t.findChild(full, "wifiSection"), "wifiRowWrapper")[3]
        t.check(t.findChild(w, "passphraseField").activeFocus, "Enter in identity moves to the passphrase")
        t.check(!reported("promptSubmit", null), "and doesn't submit")
        full.prompt = closedPrompt

        // ---------- ensureVisible ----------
        var flick = t.findChild(scroller, "wifiScroll")
        t.check(flick.height <= 80.5 && flick.interactive, "the scroll area is capped")
        t.equal(flick.contentY, 0, "it starts at the top")
        scroller.ensureVisible("saved", 1)
      }], [60, function () {
        var flick = t.findChild(scroller, "wifiScroll")
        t.check(flick.contentY > 0, "ensureVisible scrolls a saved row into view")
        scroller.ensureVisible("wifi", 0)
      }], [60, function () {
        var flick = t.findChild(scroller, "wifiScroll")
        t.equal(flick.contentY, 0, "the first Wi-Fi row brings its caption back")

        // ---------- A still pointer ----------
        full.view = withCursor(cur(false, "wifi", 0))
        full.disarmPointer()
        var rows = t.findChildren(t.findChild(full, "wifiSection"), "wifiRow")
        var pt = rows[1].mapToItem(full, 60, rows[1].height / 2)
        actions = []
        pointer.mouseMove(full, pt.x, pt.y)
        stillPoint = pt
      }], [80, function () {
        pointer.mouseMove(full, stillPoint.x + 4, stillPoint.y)
      }], [80, function () {
        t.check(reported("hover", {
          section: "wifi",
          index: 1,
          action: false
        }), "a real move over a Wi-Fi row reports hover")
        actions = []
        full.view = withCursor(cur(false, "wifi", 0))
        // same rows: nothing moves
        full.view = fullView(cur(false, "wifi", 0), wifiRows.slice(1))
      }], [80, function () {
        pointer.mouseMove(full, stillPoint.x + 4, stillPoint.y)
      }], [80, function () {
        t.equal(actions.filter(function (a) {
          return a[0] === "hover"
        }).length, 0, "a row sliding under a still pointer emits no hover")
        pointer.mouseMove(full, stillPoint.x, stillPoint.y + 5)
      }], [80, function () {
        t.check(actions.some(function (a) {
          return a[0] === "hover"
        }), "a real move after the slide reports hover again")
        // Wi-Fi arriving after the view was built (the live panel's first
        // frames) must still show the scroll area and its sections.
        bare.view = fullView(cur(false, "wifi", 0), wifiRows)
      }], [80, function () {
        t.check(t.findChild(bare, "wifiScroll").visible, "the scroll area shows once Wi-Fi arrives")
        t.check(t.findChild(bare, "wifiSection").visible, "the Wi-Fi list shows once Wi-Fi arrives")
        t.check(t.findChild(bare, "savedSection").visible, "Saved shows once its rows arrive")
      }]])

  // The Wi-Fi delegates (wrappers, then rows) before the refresh check.
  property var identityBefore: []
  // The pointer position the still-pointer check replays.
  property var stillPoint: null
}
