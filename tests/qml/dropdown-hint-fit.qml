// Every dropdown footer's key hint fits its card at the card's real
// content width (the panel's Style.space(W) less its padding and border on
// both sides, as each Panel.qml sizes it) unelided, with a 10% margin, as
// the notification center's hint does (notification-center-fit.qml). The
// Audio and Bluetooth hints are measured in their real dropdowns; the rest
// are measured in a Text styled as every footer hint is (Style.font.family
// at Style.font.caption). Every hint follows one pattern: no "tab next",
// and the Enter verb wherever Enter acts.
import QtQuick
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.audio" as Audio
import "plugins/araneadev.bluetooth" as Bluetooth
import "plugins/araneadev.notifications/InboxLogic.js" as InboxLogic
import "plugins/araneadev.power/PowerLogic.js" as PowerLogic
import "plugins/araneadev.monitor/DisplaysLogic.js" as DisplaysLogic
import "plugins/araneadev.network/NetworkLogic.js" as NetworkLogic
import "plugins/araneadev.vpn/VpnLogic.js" as VpnLogic

ShellRoot {
  id: testRoot

  QmlTest {
    id: t
  }

  // The card's content width as Panel.qml sizes it: the panel width less
  // its padding and border on both sides.
  readonly property real innerWidth: testRoot.cardInner(380)

  // The content width of a card whose panel is Style.space(PANEL) wide.
  function cardInner(panel) {
    return Style.space(panel) - 2 * Style.spacing.popupPadding - 2 * Math.max(1, Style.space(2))
  }

  FloatingWindow {
    implicitWidth: 840
    implicitHeight: 900
    visible: true

    Audio.AudioDropdown {
      id: audio
      x: 20
      y: 20
      width: testRoot.innerWidth
      view: ({
          glyph: "",
          mood: "Cranked up",
          anyAudible: true,
          toggleHint: "Mute",
          headerCursor: false,
          cursor: {
            active: false,
            section: "output",
            index: -1
          },
          output: {
            present: true,
            volume: 0.74,
            muted: false,
            level: 0.4
          },
          outputDevices: [
            {
              key: "1",
              label: "ALC236 Analog",
              glyph: "",
              detail: "",
              active: true,
              available: true
            },
            {
              key: "2",
              label: "LG ULTRAGEAR",
              glyph: "",
              detail: "",
              active: false,
              available: true
            },
            {
              key: "3",
              label: "WH-1000XM4",
              glyph: "",
              detail: "unplugged",
              active: false,
              available: false
            }
          ],
          outputDefault: {
            key: "1",
            busy: false
          },
          inputDefault: {
            key: "9",
            busy: false
          },
          inputVisible: true,
          input: {
            present: true,
            volume: 0.62,
            muted: false,
            level: 0
          },
          inputDevices: [
            {
              key: "9",
              label: "ALC236 Analog",
              glyph: "",
              detail: "",
              active: true,
              available: true
            }
          ],
          streams: [
            {
              key: "7",
              label: "Spotify",
              volume: 1.2,
              muted: false,
              current: true
            },
            {
              key: "8",
              label: "Firefox",
              volume: 0.6,
              muted: true,
              current: false
            }
          ],
          nowPlaying: {
            visible: true,
            player: "Spotify",
            title: "Midnight City",
            artist: "M83",
            album: "",
            progress: 0.4,
            playing: true,
            canPrevious: true,
            canNext: true
          }
        })
    }

    Bluetooth.BluetoothDropdown {
      id: bluetooth
      x: 440
      y: 20
      width: testRoot.innerWidth
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
    }
  }

  // HINT fits its width unelided, with a 10% margin: the live shell's font
  // and spacing scale differ from this harness.
  function checkFits(hint, name) {
    t.check(hint !== null, name + " has a key hint")
    t.check(Math.abs(hint.width - testRoot.innerWidth) < 0.5, name + "'s hint spans the card's content width (" + hint.width + ")")
    t.check(!hint.truncated && hint.lineCount === 1, name + "'s hint is not elided")
    t.check(hint.implicitWidth <= hint.width * 0.9, name + "'s hint fits with a margin (" + hint.implicitWidth + " <= 0.9 * " + hint.width + ")")
  }

  // A footer hint as every dropdown styles it, sized by the checks.
  Text {
    id: probe
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  // Every other dropdown's hints, with the panel width (Style.space units)
  // their card is built at.
  function otherHints() {
    var list = []
    var add = function (name, panel, text) {
      list.push({
        name: name,
        panel: panel,
        text: text
      })
    }
    add("Notifications", 380, InboxLogic.centerKeyHint(3))
    add("Notifications (empty)", 380, InboxLogic.centerKeyHint(0))
    add("Power", 380, PowerLogic.keyHint("profiles"))
    add("Power (none)", 380, PowerLogic.keyHint(""))
    var displaySections = ["nightlight", "scale", "brightness", ""]
    displaySections.forEach(function (section) {
      add("Displays " + section, 380, DisplaysLogic.keyHint(section, "switch"))
    })
    var networkSections = ["saved", "header", "wifi"]
    networkSections.forEach(function (section) {
      add("Network " + section, 380, NetworkLogic.keyHint(section))
    })
    add("VPN app", 380, VpnLogic.hintFor(false, "available", "app", true, true))
    add("VPN connected", 380, VpnLogic.hintFor(false, "connected", "vpn", true, true))
    add("VPN available", 380, VpnLogic.hintFor(false, "available", "vpn", true, true))
    add("VPN unchosen", 380, VpnLogic.hintFor(false, "available", "vpn", true, false))
    add("VPN empty", 380, VpnLogic.hintFor(false, "", "", false, false))
    add("VPN prompt", 380, VpnLogic.hintFor(true, "available", "vpn", true, true))
    add("Health", 380, "↑↓ move · enter open")
    add("Workspaces", 380, "↑↓ move · enter focus · wheel cycle")
    add("Updates", 380, "↑↓ move · enter select · r refresh")
    add("Agents", 380, "h/l agent · enter/r refresh · ↑↓ scroll")
    add("Weather", 380, "enter select · e edit place · r refresh")
    add("Weather (editing)", 380, "↑↓ pick · enter save · esc cancel")
    add("Clock", 440, "←→ month · ↑↓ year · t today")
    add("Tray menu", 320, String.fromCodePoint(0x2191, 0x2193) + " move " + String.fromCodePoint(0xB7) + " " + String.fromCodePoint(0x2192) + " open " + String.fromCodePoint(0xB7) + " " + String.fromCodePoint(0x2190) + " back " + String.fromCodePoint(0xB7) + " enter select")
    add("Tray manage", 340, String.fromCodePoint(0x2191, 0x2193) + " move " + String.fromCodePoint(0xB7) + " " + String.fromCodePoint(0x2190, 0x2192) + " pin / hide " + String.fromCodePoint(0xB7) + " enter toggle")
    return list
  }

  Component.onCompleted: t.step(300, function () {
    otherHints().forEach(function (hint) {
      probe.width = testRoot.cardInner(hint.panel)
      probe.text = hint.text
      t.check(probe.text.indexOf("tab next") < 0, hint.name + "'s hint drops tab next, as every hint does")
      t.check(!probe.truncated && probe.lineCount === 1 && probe.implicitWidth <= probe.width * 0.9, hint.name + "'s hint fits its card with a margin (" + probe.implicitWidth + " <= 0.9 * " + probe.width + ")")
    })
    var audioHint = t.findChild(audio, "keyHint")
    checkFits(audioHint, "Audio")
    t.equal(audioHint.text, "↑↓ move · enter select · ←→ adjust · m mute", "the Audio hint names move, Enter, adjust and mute")
    var bluetoothHint = t.findChild(bluetooth, "keyHint")
    checkFits(bluetoothHint, "Bluetooth")
    t.equal(bluetoothHint.text, "↑↓ move · enter connect · x forget · b power", "the Bluetooth hint names move, Enter, forget and power")
    t.done()
  })
}
