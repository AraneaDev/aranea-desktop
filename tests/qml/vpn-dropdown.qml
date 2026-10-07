// The assembled Aranea VPN dropdown, driven by a plain view object in a
// real window with real pointer clicks and key presses: the header reads
// "VPN" with its caption; the pinned CONNECTED section and the scrolling
// AVAILABLE section show and hide on their rows (the empty text takes
// over without any); NetworkManager rows carry a switch and own-app rows
// an "open app" chip, and row, switch and chip clicks emit toggle/openApp
// with the row's index and key, but never within 300 ms of a delegate being
// built; a row's status replaces its type (a failure urgent, a busy row
// breathing, push 2FA reading "Connecting… approve on phone"); session
// details (IP, Server when known, Up) and the traffic graph show only under
// connected rows; showcase names relabel rows in display order; the
// credential prompt opens under its row with a read-only username (or "No
// username in this profile"), the password focused, Enter moving to the
// 2FA code and submitting from there, Esc cancelling, typing emitting
// passwordEdited/codeEdited and the connect button (settled like a row)
// emitting promptConnect, busy and failed swapping the fields for a
// message; changing only status, sessions, graphs or prompt keeps the row
// delegates and a half-typed password; no outline without cursor.active
// and exactly one with it; every trailing element ends on one right
// content edge; ensureVisible scrolls Available; and a row sliding under a
// still pointer emits no hover.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.vpn" as Vpn
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

  // The NetworkManager VPN glyph.
  readonly property string vpnGlyph: String.fromCodePoint(0xf0582)
  // The own-app VPN glyph.
  readonly property string appGlyph: String.fromCodePoint(0xf03cc)

  // The connected rows, built once so a view rebuilt with them keeps the
  // same model (as Panel's vpnView does).
  readonly property var connectedRows: [
    {
      key: "uuid-office",
      kind: "nm",
      name: "Office (Firebox)",
      glyph: vpnGlyph,
      label: "OpenVPN"
    },
    {
      key: "app:Azure (Contoso)",
      kind: "app",
      name: "Azure (Contoso)",
      glyph: appGlyph,
      label: "Azure VPN Client"
    }
  ]

  // The available rows, built once.
  readonly property var availableRows: [
    {
      key: "uuid-client-a",
      kind: "nm",
      name: "Client A",
      glyph: vpnGlyph,
      label: "OpenVPN"
    },
    {
      key: "uuid-gp",
      kind: "nm",
      name: "GlobalProtect (HQ)",
      glyph: vpnGlyph,
      label: "OpenConnect"
    },
    {
      key: "app:Azure (Fabrikam)",
      kind: "app",
      name: "Azure (Fabrikam)",
      glyph: appGlyph,
      label: "Azure VPN Client"
    }
  ]

  // A view with CURSOR, CONNECTED and AVAILABLE rows.
  function viewOf(cursor, connected, available) {
    return {
      header: {
        glyph: vpnGlyph,
        caption: "2 of 5 connected",
        iconState: "up"
      },
      connected: connected,
      available: available,
      cursor: cursor,
      emptyText: "",
      keyHint: "↑↓ move · enter connect · esc close"
    }
  }

  // The full view, keeping its rows, with the cursor C.
  function withCursor(c) {
    return viewOf(c, connectedRows, availableRows)
  }

  // A cursor object: ACTIVE on SECTION's INDEX.
  function cur(active, section, index) {
    return {
      active: active,
      section: section,
      index: index
    }
  }

  // A closed prompt.
  readonly property var closedPrompt: ({
      key: "",
      username: "",
      password: "",
      code: "",
      busy: false,
      failed: false,
      failedText: ""
    })

  // The open prompt for KEY with FIELDS merged in.
  function promptFor(key, fields) {
    var p = {
      key: key,
      username: "tim",
      password: "",
      code: "",
      busy: false,
      failed: false,
      failedText: ""
    }
    for (var k in fields)
      p[k] = fields[k]
    return p
  }

  // The fixture statuses: the GlobalProtect row waiting on push 2FA.
  readonly property var pushStatus: ({
      "uuid-gp": {
        text: "Connecting… approve on phone",
        busy: true,
        failed: false
      }
    })

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

  // The row wrappers of SECTION ("connected" or "available") in full.
  function wrappersOf(section) {
    return t.findChildren(t.findChild(full, section + "Section"), "vpnRowWrapper")
  }

  // The rows of SECTION in full.
  function rowsOf(section) {
    return t.findChildren(t.findChild(full, section + "Section"), "vpnRow")
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
    implicitWidth: 420
    implicitHeight: 2000
    visible: true

    Column {
      x: 20
      width: 380
      spacing: 20

      Vpn.VpnDropdown {
        id: full
        width: 380
        maxScrollHeight: 1200
        view: withCursor(cur(false, "available", 0))
        status: ({
            "uuid-client-a": {
              text: "Couldn't connect",
              failed: true,
              busy: false
            },
            "uuid-gp": {
              text: "Connecting… approve on phone",
              failed: false,
              busy: true
            }
          })
        sessions: ({
            "uuid-office": {
              ip: "10.20.4.17",
              server: "vpn.example.com",
              up: "1 h 12 min"
            },
            "app:Azure (Contoso)": {
              ip: "172.16.8.40",
              server: "",
              up: "23 min"
            },
            "uuid-client-a": {
              ip: "10.0.0.9",
              server: "stale.example.com",
              up: "5 min"
            }
          })
        graphs: ({
            "uuid-office": [
              {
                rx: 1000,
                tx: 10
              },
              {
                rx: 4000,
                tx: 40
              }
            ],
            "uuid-client-a": [
              {
                rx: 1000,
                tx: 10
              }
            ]
          })
        prompt: closedPrompt
        onAction: function (name, arg) {
          actions.push([name, arg])
          // Echo edits back the way Panel does, so the fields' bindings to
          // prompt.password/code see what was typed.
          if (name === "passwordEdited")
            full.prompt = promptFor(full.prompt.key, {
              username: full.prompt.username,
              password: arg.text,
              code: full.prompt.code
            })
          else if (name === "codeEdited")
            full.prompt = promptFor(full.prompt.key, {
              username: full.prompt.username,
              password: full.prompt.password,
              code: arg.text
            })
        }
      }

      // No VPNs at all.
      Vpn.VpnDropdown {
        id: bare
        width: 380
        view: ({
            header: {
              glyph: "",
              caption: "Not connected",
              iconState: "idle"
            },
            connected: [],
            available: [],
            cursor: {
              active: false,
              section: "",
              index: -1
            },
            emptyText: "No VPNs yet",
            keyHint: "esc close"
          })
      }

      // A short scroll area for ensureVisible.
      Vpn.VpnDropdown {
        id: scroller
        width: 380
        maxScrollHeight: 40
        view: withCursor(cur(false, "available", 0))
        onAction: function (name, arg) {
          if (name !== "hover")
            scrollActions.push([name, arg])
        }
      }
    }
  }

  Component.onCompleted: run([[350, function () {
        // ---------- Header and sections ----------
        var header = t.findChild(full, "vpnHeader")
        t.check(header !== null && header.visible, "the header shows")
        t.equal(header.title, "VPN", "the header title")
        t.equal(t.findChild(header, "headerCaption").text, "2 of 5 connected", "the header caption")
        t.check(Qt.colorEqual(header.glyphColor, Aranea.DesignTokens.accent), "an up VPN lights the header glyph")
        t.check(Qt.colorEqual(t.findChild(bare, "vpnHeader").glyphColor, Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)), "an idle header glyph is dim")
        t.equal(t.findChild(header, "headerTrailing").children.length, 0, "the header has no switch")
        var conn = t.findChild(full, "connectedSection")
        var avail = t.findChild(full, "availableSection")
        t.check(conn.visible && avail.visible, "both sections show with rows")
        t.equal(t.findChild(conn, "sectionCaption").text, "CONNECTED", "the Connected caption")
        t.equal(t.findChild(conn, "sectionCount").text, "2", "the Connected count")
        t.equal(t.findChild(avail, "sectionCaption").text, "AVAILABLE", "the Available caption")
        t.equal(t.findChild(avail, "sectionCount").text, "3", "the Available count")
        var scroll = t.findChild(full, "vpnScroll")
        t.check(t.findChild(scroll, "availableSection") !== null, "Available scrolls")
        t.check(t.findChild(scroll, "connectedSection") === null, "Connected is pinned")
        t.check(!t.findChild(bare, "connectedSection").visible && !t.findChild(bare, "availableSection").visible, "no rows hides both sections")
        t.check(!t.findChild(bare, "vpnScroll").visible, "and the scroll area")
        var empty = t.findChild(bare, "emptyText")
        t.check(empty.visible && empty.text === "No VPNs yet", "no rows shows the empty text")
        t.check(!t.findChild(full, "emptyText").visible, "rows hide the empty text")
        t.equal(t.findChild(full, "keyHint").text, "↑↓ move · enter connect · esc close", "the key hint is the view's")
        t.equal(t.findChild(bare, "keyHint").text, "esc close", "the bare key hint")

        // ---------- Rows ----------
        var crows = rowsOf("connected")
        var arows = rowsOf("available")
        t.equal(crows.map(function (r) {
          return r.label
        }), ["Office (Firebox)", "Azure (Contoso)"], "connected rows in order")
        t.equal(arows.map(function (r) {
          return r.label
        }), ["Client A", "GlobalProtect (HQ)", "Azure (Fabrikam)"], "available rows in order")
        t.check(crows.every(function (r) {
          return r.active
        }) && arows.every(function (r) {
          return !r.active
        }), "connected rows are lit, available ones not")
        t.check(crows.every(function (r) {
          return t.findChild(r, "selectedFill").visible
        }) && arows.every(function (r) {
          return !t.findChild(r, "selectedFill").visible
        }), "connected rows carry the selected highlight, available ones not")
        t.equal(crows[0].glyph, vpnGlyph, "rows carry their glyph")
        t.equal(crows.concat(arows).map(function (r) {
          return !!t.findChild(r, "vpnSwitch")
        }), [true, false, true, true, false], "NetworkManager rows have a switch")
        t.equal(crows.concat(arows).map(function (r) {
          return !!t.findChild(r, "openAppChip")
        }), [false, true, false, false, true], "own-app rows have a chip")
        t.equal(t.findChild(crows[1], "openAppChip").text, "open app", "the chip reads open app")
        t.check(t.findChild(crows[0], "vpnSwitch").checked && !t.findChild(arows[0], "vpnSwitch").checked, "the switch shows the row's state")
        t.equal(crows[0].detail, "OpenVPN", "the type is the detail")
        t.equal(crows[1].detail, "Azure VPN Client", "an app's label is its detail")
        t.equal(arows[0].detail, "Couldn't connect", "a status replaces the type")
        t.check(Qt.colorEqual(t.findChild(arows[0], "detailText").color, Aranea.DesignTokens.urgent), "a failure is urgent")
        t.check(arows[1].busy && !arows[0].busy, "a busy row breathes")
        t.equal(arows[1].detail, "Connecting… approve on phone", "push 2FA reads approve on phone")

        // ---------- Sessions and graphs ----------
        var cw = wrappersOf("connected")
        var aw = wrappersOf("available")
        var office = t.findChild(cw[0], "vpnSession")
        t.check(office.visible, "a connected row shows its session")
        t.equal(t.findChild(office, "sessionIp").text, "10.20.4.17", "the session IP")
        t.equal(t.findChild(office, "sessionServer").text, "vpn.example.com", "the session server")
        t.equal(t.findChild(office, "sessionUp").text, "1 h 12 min", "the session uptime")
        t.check(t.findChild(office, "linkGraph").visible, "a connected row with samples shows its graph")
        t.equal(t.findChild(office, "linkGraph").samples.length, 2, "the graph gets the row's samples")
        var azure = t.findChild(cw[1], "vpnSession")
        t.check(azure.visible && t.findChild(azure, "sessionIp").text === "172.16.8.40", "an app session shows its IP")
        t.check(!t.findChild(azure, "sessionServer").visible && !t.findChild(azure, "serverKey").visible, "no Server line without a server")
        t.check(t.findChild(azure, "sessionUp").visible, "the app's uptime shows")
        t.check(!t.findChild(azure, "linkGraph").visible, "no graph without samples")
        t.equal(shown(t.findChild(full, "availableSection"), "vpnSession").length, 0, "available rows never show a session")
        t.equal(shown(t.findChild(full, "availableSection"), "linkGraph").length, 0, "or a graph")

        // ---------- No outline without the cursor ----------
        t.equal(litOutlines(full), 0, "an inactive cursor draws no outline")

        // ---------- Clicks ----------
        actions = []
        pointer.mouseClick(crows[0], 60, crows[0].height / 2)
        t.check(reported("toggle", {
          index: 0,
          key: "uuid-office"
        }), "an NM row click emits toggle with the row's key")
        actions = []
        pointer.mouseClick(t.findChild(crows[0], "vpnSwitch"))
        t.check(reported("toggle", {
          index: 0,
          key: "uuid-office"
        }), "the switch emits toggle with the row's key")
        actions = []
        pointer.mouseClick(t.findChild(arows[1], "vpnSwitch"))
        t.check(reported("toggle", {
          index: 1,
          key: "uuid-gp"
        }), "an available switch names its row")
        actions = []
        pointer.mouseClick(crows[1], 60, crows[1].height / 2)
        t.check(reported("openApp", {
          index: 1,
          key: "app:Azure (Contoso)"
        }), "an app row click emits openApp")
        actions = []
        pointer.mouseClick(t.findChild(arows[2], "openAppChip"))
        t.check(reported("openApp", {
          index: 2,
          key: "app:Azure (Fabrikam)"
        }) && nonHover().length === 1, "the chip emits openApp once")
        t.equal(litOutlines(full), 0, "clicks draw no outline")

        // ---------- Showcase names ----------
        full.showcaseNames = ["Alpha", "Beta", "Gamma"]
        t.equal(rowsOf("connected").concat(rowsOf("available")).map(function (r) {
          return r.label
        }), ["Alpha", "Beta", "Gamma", "VPN 4", "VPN 5"], "showcase names relabel rows in display order")
        full.showcaseNames = []
        t.equal(rowsOf("available")[0].label, "Client A", "without showcase names the real ones return")

        // ---------- One outline per cursor ----------
        var cases = [cur(true, "connected", 0), cur(true, "connected", 1), cur(true, "available", 0), cur(true, "available", 2)]
        for (var i = 0; i < cases.length; i++) {
          full.view = withCursor(cases[i])
          t.equal(litOutlines(full), 1, "an active cursor on " + cases[i].section + " " + cases[i].index + " draws exactly one outline")
        }
        t.check(rowsOf("available")[2].hasCursor, "on the row it names")
        full.view = withCursor(cur(false, "available", 2))
        t.equal(litOutlines(full), 0, "an inactive cursor on a row draws none")

        // ---------- One right content edge ----------
        var edge = rightEdge(full, full)
        var crows2 = rowsOf("connected")
        var arows2 = rowsOf("available")
        var trailing = [["NM switch", t.findChild(crows2[0], "vpnSwitch")], ["app chip", t.findChild(crows2[1], "openAppChip")], ["available switch", t.findChild(arows2[0], "vpnSwitch")], ["available chip", t.findChild(arows2[2], "openAppChip")], ["session", t.findChild(wrappersOf("connected")[0], "vpnSession")], ["graph", t.findChild(wrappersOf("connected")[0], "linkGraph")], ["row", arows2[1]]]
        for (var j = 0; j < trailing.length; j++)
          t.check(trailing[j][1] && Math.abs(rightEdge(trailing[j][1], full) - edge) < 0.5, trailing[j][0] + " ends on the content edge")

        // ---------- The credential prompt ----------
        actions = []
        full.prompt = promptFor("uuid-client-a", {})
      }], [150, function () {
        var panels = shown(full, "promptPanel")
        t.equal(panels.length, 1, "the prompt opens under one row")
        var w = wrappersOf("available")[0]
        t.check(t.findChild(w, "promptPanel").visible, "under the row whose key it names")
        t.check(Math.abs(rightEdge(panels[0], full) - rightEdge(full, full)) < 0.5, "the prompt ends on the content edge")
        t.equal(rowsOf("available")[0].detail, "", "the row's status hides while its prompt is open")
        var user = t.findChild(w, "usernameField")
        t.check(user.visible && user.text === "tim", "the username shows read-only")
        t.equal(t.findChild(w, "usernameLabel").text, "Username", "with its label")
        t.check(user.activeFocus === false && !("echoMode" in user), "the username can't be edited")
        var pw = t.findChild(w, "passwordField")
        t.check(pw.visible && pw.activeFocus, "opening the prompt focuses the password")
        t.equal(pw.placeholderText, "Password", "the password placeholder")
        t.equal(pw.echoMode, TextInput.Password, "the password is echoed as a password")
        var code = t.findChild(w, "codeField")
        t.check(code.visible, "a 2FA code field")
        t.equal(code.placeholderText, "2FA code (optional)", "the code placeholder")
        t.equal(code.echoMode, TextInput.Normal, "the code is shown")
        t.check(user.mapToItem(full, 0, 0).y < pw.mapToItem(full, 0, 0).y && pw.mapToItem(full, 0, 0).y < code.mapToItem(full, 0, 0).y, "username, password, then code")
        t.check(Math.abs(pw.width - code.width) < 0.5, "the password is as wide as the code beside the connect button")
        var btn = t.findChild(w, "connectButton")
        t.equal(btn.tooltipText, "Connect", "the connect button explains itself")
        t.check(!btn.enabled, "connect waits for a password")
        pointer.keyClick(Qt.Key_A)
        pointer.keyClick(Qt.Key_B)
      }], [60, function () {
        var w = wrappersOf("available")[0]
        var pw = t.findChild(w, "passwordField")
        t.equal(pw.text, "ab", "typing reaches the password field")
        t.check(reported("passwordEdited", {
          text: "a"
        }) && reported("passwordEdited", {
          text: "ab"
        }), "typing emits passwordEdited")
        t.check(t.findChild(w, "connectButton").enabled, "a password enables connect (the code is optional)")
        actions = []
        pointer.keyClick(Qt.Key_Return)
      }], [60, function () {
        var w = wrappersOf("available")[0]
        t.check(t.findChild(w, "codeField").activeFocus, "Enter in the password moves to the code")
        t.equal(nonHover().length, 0, "and doesn't submit")
        pointer.keyClick(Qt.Key_1)
      }], [60, function () {
        t.check(reported("codeEdited", {
          text: "1"
        }), "typing emits codeEdited")

        // ---------- Identity across refreshes ----------
        identityBefore = wrappersOf("connected").concat(rowsOf("connected"), wrappersOf("available"), rowsOf("available"))
        var pw = t.findChild(wrappersOf("available")[0], "passwordField")
        pw.forceActiveFocus()
        // A selection only the same field instance can keep.
        pw.select(0, 1)
        full.status = pushStatus
        full.sessions = {
          "uuid-office": {
            ip: "10.20.4.17",
            server: "vpn.example.com",
            up: "1 h 13 min"
          }
        }
        full.graphs = {
          "uuid-office": [
            {
              rx: 1000,
              tx: 10
            },
            {
              rx: 4000,
              tx: 40
            },
            {
              rx: 2000,
              tx: 20
            }
          ]
        }
        full.prompt = promptFor("uuid-client-a", {
          password: "ab",
          code: "1"
        })
      }], [350, function () {
        // (Past 300 ms: dropping the Azure session shrank Connected, which
        // settles the connect button like any layout shift.)
        var now = wrappersOf("connected").concat(rowsOf("connected"), wrappersOf("available"), rowsOf("available"))
        t.check(now.length === 10 && identityBefore.length === 10 && identityBefore.every(function (w, k) {
          return w === now[k]
        }), "status, sessions, graphs and prompt keep the same row delegates")
        var pw = t.findChild(wrappersOf("available")[0], "passwordField")
        t.equal(pw.text, "ab", "a half-typed password survives the refresh")
        t.equal(pw.selectedText, "a", "in the same field (its selection kept)")
        t.check(pw.activeFocus, "and keeps its focus")
        t.equal(t.findChild(wrappersOf("connected")[0], "sessionUp").text, "1 h 13 min", "a new uptime shows")
        t.equal(t.findChild(wrappersOf("connected")[0], "linkGraph").samples.length, 3, "new samples reach the graph")
        pw.deselect()

        actions = []
        t.findChild(wrappersOf("available")[0], "codeField").forceActiveFocus()
        pointer.keyClick(Qt.Key_Return)
        t.check(reported("promptSubmit", null), "Enter in the code emits promptSubmit")
        actions = []
        pointer.mouseClick(t.findChild(wrappersOf("available")[0], "connectButton"))
        t.check(reported("promptConnect", null) && !reported("promptSubmit", null), "the connect button emits promptConnect (a pointer action)")
        t.findChild(wrappersOf("available")[0], "passwordField").forceActiveFocus()
        actions = []
        pointer.keyClick(Qt.Key_Escape)
        t.check(reported("promptCancel", null), "Esc in the password emits promptCancel")
        t.findChild(wrappersOf("available")[0], "codeField").forceActiveFocus()
        actions = []
        pointer.keyClick(Qt.Key_Escape)
        t.check(reported("promptCancel", null), "Esc in the code emits promptCancel")

        // Busy: the push-2FA status reads in the prompt.
        full.prompt = promptFor("uuid-gp", {
          password: "ab",
          busy: true
        })
      }], [60, function () {
        var w = wrappersOf("available")[1]
        var status = t.findChild(w, "promptStatus")
        t.check(status.visible && status.text === "Connecting… approve on phone", "a busy prompt shows the push-2FA status")
        t.check(!t.findChild(w, "passwordField").visible && !t.findChild(w, "connectButton").visible, "busy hides the fields and button")
        full.status = {}
        t.equal(status.text, "Connecting…", "busy without a status reads Connecting…")
        full.prompt = promptFor("uuid-gp", {
          password: "ab",
          failed: true,
          failedText: "Couldn't connect"
        })
        t.check(status.visible && status.text === "Couldn't connect", "failed shows its text")
        t.check(Qt.colorEqual(status.color, Aranea.DesignTokens.urgent), "in the urgent colour")
        full.prompt = closedPrompt
      }], [60, function () {
        t.equal(shown(full, "promptPanel").length, 0, "a closed prompt shows nowhere")
        // No username in the profile; the prompt reopens on a fresh key.
        full.prompt = promptFor("uuid-gp", {
          username: "",
          password: "x"
        })
        actions = []
        var btn = t.findChild(wrappersOf("available")[1], "connectButton")
        pointer.mouseClick(btn)
        t.equal(nonHover().length, 0, "a connect click right after the prompt opened is ignored")
      }], [350, function () {
        var w = wrappersOf("available")[1]
        t.equal(t.findChild(w, "usernameField").text, "No username in this profile", "an empty username says so")
        t.check(t.findChild(w, "passwordField").activeFocus, "the password is focused (the username is skipped)")
        actions = []
        pointer.mouseClick(t.findChild(w, "connectButton"))
        t.check(reported("promptConnect", null), "a settled connect click emits promptConnect")
        full.prompt = closedPrompt

        // ---------- Fresh delegates ignore clicks ----------
        // A re-sort rebuilds the delegates (equal rows would keep them).
        full.view = viewOf(cur(false, "available", 0), [connectedRows[1], connectedRows[0]], availableRows.slice().reverse())
      }], [30, function () {
        // The old delegates are gone by now; the new ones are 30 ms old.
        var crows = rowsOf("connected")
        var arows = rowsOf("available")
        t.equal(crows.map(function (r) {
          return r.label
        }).concat(arows.map(function (r) {
          return r.label
        })), ["Azure (Contoso)", "Office (Firebox)", "Azure (Fabrikam)", "GlobalProtect (HQ)", "Client A"], "the re-sorted rows")
        actions = []
        pointer.mouseClick(crows[0], 60, crows[0].height / 2)
        pointer.mouseClick(t.findChild(arows[1], "vpnSwitch"))
        pointer.mouseClick(t.findChild(crows[0], "openAppChip"))
        pointer.mouseClick(arows[2], 60, arows[2].height / 2)
        t.equal(nonHover().length, 0, "clicks within 300 ms of a rebuild are ignored (row, switch, chip)")
      }], [350, function () {
        var crows = rowsOf("connected")
        var arows = rowsOf("available")
        actions = []
        pointer.mouseClick(t.findChild(arows[2], "vpnSwitch"))
        pointer.mouseClick(t.findChild(crows[0], "openAppChip"))
        t.check(reported("toggle", {
          index: 2,
          key: "uuid-client-a"
        }) && reported("openApp", {
          index: 0,
          key: "app:Azure (Contoso)"
        }), "settled delegates take clicks again")
        full.view = withCursor(cur(false, "available", 0))

        // ---------- ensureVisible ----------
        var flick = t.findChild(scroller, "vpnScroll")
        t.check(flick.height <= 40.5 && flick.interactive, "the scroll area is capped")
        t.equal(flick.contentY, 0, "it starts at the top")
        scroller.ensureVisible("available", 2)
      }], [60, function () {
        var flick = t.findChild(scroller, "vpnScroll")
        t.check(flick.contentY > 0, "ensureVisible scrolls an available row into view")
        scroller.ensureVisible("available", 0)
      }], [60, function () {
        t.equal(t.findChild(scroller, "vpnScroll").contentY, 0, "the first available row brings its caption back")

        // ---------- A still pointer ----------
        full.disarmPointer()
        var arows = rowsOf("available")
        var pt = arows[1].mapToItem(full, 60, arows[1].height / 2)
        actions = []
        pointer.mouseMove(full, pt.x, pt.y)
        stillPoint = pt
      }], [80, function () {
        pointer.mouseMove(full, stillPoint.x + 4, stillPoint.y)
      }], [80, function () {
        t.check(reported("hover", {
          section: "available",
          index: 1,
          key: "uuid-gp"
        }), "a real move over a row reports hover with its key")
        actions = []
        full.view = viewOf(cur(false, "available", 0), connectedRows, availableRows.slice(1))
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

        // ---------- Layout shifts under a still pointer ----------
        full.view = withCursor(cur(false, "available", 0))
        full.prompt = closedPrompt
      }], [400, function () {
        full.disarmPointer()
        var arows = rowsOf("available")
        stillPoint = arows[1].mapToItem(full, 60, arows[1].height / 2)
        pointer.mouseMove(full, stillPoint.x, stillPoint.y)
      }], [80, function () {
        pointer.mouseMove(full, stillPoint.x + 4, stillPoint.y)
      }], [400, function () {
        t.check(reported("hover", {
          section: "available",
          index: 1,
          key: "uuid-gp"
        }), "the pointer rests on GlobalProtect")
        shiftedFrom = rowsOf("available")[1].mapToItem(full, 0, 0).y
        actions = []
        // The Azure app session gains a Server line and its first samples:
        // the Connected block grows without rebuilding a delegate.
        full.sessions = {
          "uuid-office": {
            ip: "10.20.4.17",
            server: "vpn.example.com",
            up: "1 h 13 min"
          },
          "app:Azure (Contoso)": {
            ip: "172.16.8.40",
            server: "gw.contoso.example",
            up: "23 min"
          }
        }
        full.graphs = {
          "app:Azure (Contoso)": [
            {
              rx: 1000,
              tx: 10
            }
          ]
        }
      }], [60, function () {
        t.check(rowsOf("available")[1].mapToItem(full, 0, 0).y > shiftedFrom, "the session grew the rows down under the still pointer")
        pointer.mouseClick(full, stillPoint.x + 4, stillPoint.y)
        t.equal(nonHover().length, 0, "a click within 300 ms of a session growing is ignored")
      }], [350, function () {
        pointer.mouseClick(full, stillPoint.x + 4, stillPoint.y)
        t.equal(nonHover().length, 1, "a click 300 ms after the growth is accepted")
        actions = []
        // The prompt opens on the row above the pointer's.
        full.prompt = promptFor("uuid-client-a", {})
      }], [60, function () {
        t.check(shown(wrappersOf("available")[0], "promptPanel").length === 1, "the prompt opened above the pointer's row")
        pointer.mouseClick(full, stillPoint.x + 4, stillPoint.y)
        t.equal(nonHover().length, 0, "a click within 300 ms of a prompt opening above the row is ignored")
      }], [350, function () {
        pointer.mouseClick(full, stillPoint.x + 4, stillPoint.y)
        t.equal(nonHover().length, 1, "a click 300 ms after the prompt opened is accepted")
        full.prompt = closedPrompt
        actions = []
        // A scroll moves Available's rows under the pointer too.
        var flick = t.findChild(scroller, "vpnScroll")
        scrollPoint = flick.mapToItem(scroller, 60, flick.height / 2)
        scroller.ensureVisible("available", 2)
      }], [60, function () {
        t.check(t.findChild(scroller, "vpnScroll").contentY > 0, "the scroll area scrolled")
        scrollActions = []
        pointer.mouseClick(scroller, scrollPoint.x, scrollPoint.y)
        t.equal(scrollActions.length, 0, "a click within 300 ms of a scroll is ignored")
      }], [350, function () {
        pointer.mouseClick(scroller, scrollPoint.x, scrollPoint.y)
        t.equal(scrollActions.length, 1, "a click 300 ms after the scroll is accepted")

        // ---------- Enter with the next field not registered yet ----------
        full.prompt = promptFor("uuid-client-a", {})
      }], [150, function () {
        var panel = shown(wrappersOf("available")[0], "promptPanel")[0]
        var code = panel.inputs[2]
        delete panel.inputs[2]
        actions = []
        panel.advance(1)
        panel.inputs[2] = code
        t.equal(nonHover().length, 0, "Enter with the next field missing neither throws nor submits")
        full.prompt = closedPrompt
      }]])

  // The available row's position before the session grew.
  property real shiftedFrom: 0
  // The middle of the scroller's scroll area, which a scroll moves rows under.
  property var scrollPoint: null
  // Actions reported by scroller, as [name, arg], other than hover.
  property var scrollActions: []

  // The row delegates before the refresh check.
  property var identityBefore: []
  // The pointer position the still-pointer check replays.
  property var stillPoint: null
}
