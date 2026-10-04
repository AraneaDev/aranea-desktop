// The Audio and Bluetooth dropdown footers' key hints fit the card at its
// real content width (the panel's Style.space(380) less its padding and
// border on both sides, as Panel.qml sizes it) unelided, with a 10%
// margin, as the notification center's hint does
// (notification-center-fit.qml).
import QtQuick
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.audio" as Audio
import "plugins/araneadev.bluetooth" as Bluetooth

ShellRoot {
  id: testRoot

  QmlTest {
    id: t
  }

  // The card's content width as Panel.qml sizes it: the panel width less
  // its padding and border on both sides.
  readonly property real innerWidth: Style.space(380) - 2 * Style.spacing.popupPadding - 2 * Math.max(1, Style.space(2))

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

  Component.onCompleted: t.step(300, function () {
    var audioHint = t.findChild(audio, "keyHint")
    checkFits(audioHint, "Audio")
    t.equal(audioHint.text, "↑↓ move · ←→ adjust · m mute · tab next", "the Audio hint keeps move, adjust, mute and tab")
    var bluetoothHint = t.findChild(bluetooth, "keyHint")
    checkFits(bluetoothHint, "Bluetooth")
    t.equal(bluetoothHint.text, "↑↓ move · x forget · b power · tab next", "the Bluetooth hint keeps move, forget, power and tab")
    t.done()
  })
}
