// The Aranea audio view, driven by a plain view object: devices listed
// with the active one marked and unplugged ones never chosen, actions
// emitted for mute and device picks, empty channels and sections hidden,
// Now playing only with a player, and one right content edge (audio-1).
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.audio" as Audio

ShellRoot {
  QmlTest {
    id: t
  }

  // Actions reported by full's action signal, in emission order.
  property var actions: []

  Audio.AudioDropdown {
    id: full
    width: 360
    view: ({
        glyph: "",
        mood: "Cranked up",
        anyAudible: true,
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
    onAction: function (name, arg) {
      actions.push([name, arg])
    }
  }

  Audio.AudioDropdown {
    id: bare
    width: 360
    view: ({
        glyph: "",
        mood: "Muted",
        anyAudible: false,
        headerCursor: false,
        cursor: {
          active: false,
          section: "output",
          index: -1
        },
        output: {
          present: false,
          volume: 0,
          muted: false,
          level: 0
        },
        outputDevices: [],
        inputVisible: false,
        input: {
          present: false,
          volume: 0,
          muted: false,
          level: 0
        },
        inputDevices: [],
        streams: [],
        nowPlaying: {
          visible: false,
          player: "",
          title: "",
          artist: "",
          album: "",
          progress: -1,
          playing: false,
          canPrevious: false,
          canNext: false
        }
      })
  }

  // Right edge of ITEM in full's coordinates.
  function rightEdge(item) {
    return item.mapToItem(full, item.width, 0).x
  }

  Component.onCompleted: t.step(300, function () {
    var output = t.findChild(full, "outputSection")
    var rows = t.findChildren(output, "deviceRow")
    t.equal(rows.length, 3, "all three outputs are listed, unplugged included")
    t.check(rows[0].active && !rows[1].active, "the active output is marked")
    rows[2].activate()
    rows[1].activate()
    t.equal(JSON.stringify(actions), JSON.stringify([["outputDevice", 1]]), "only the available device is chosen")
    t.findChild(output, "channelSlider").rightClicked()
    t.equal(actions[actions.length - 1][0], "outputMute", "right-click on the output slider mutes output")
    var sources = t.findChild(full, "sourcesSection")
    var streamSlider = t.findChildren(sources, "streamSlider")[0]
    t.equal(streamSlider.maximum, 1.5, "streams go to 150%")
    t.check(t.findChild(full, "nowPlaying").visible, "now playing shows with a player")
    t.check(!t.findChild(bare, "nowPlaying").visible, "now playing hides without one")
    t.check(!t.findChild(bare, "sourcesSection").visible, "sources hide without streams")
    t.check(!t.findChild(bare, "inputSection").visible, "input hides without a source")
    t.check(t.findChild(t.findChild(bare, "outputSection"), "emptyText").visible, "a missing output says so")
    var edge = rightEdge(full)
    var trailing = [t.findChild(full, "headerTrailing"), t.findChild(output, "levelText"), t.findChild(output, "channelSlider"), rows[0], streamSlider]
    for (var i = 0; i < trailing.length; i++)
      t.check(Math.abs(rightEdge(trailing[i]) - edge) < 0.5, "trailing element " + i + " ends on the content edge")
    t.done()
  })
}
