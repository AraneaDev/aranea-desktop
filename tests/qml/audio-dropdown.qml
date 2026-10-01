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

  // VIEW with only output.level changed to LEVEL; every row array is reused.
  function levelTick(view, level) {
    var next = {}
    for (var key in view)
      next[key] = view[key]
    next.output = {
      present: view.output.present,
      volume: view.output.volume,
      muted: view.output.muted,
      level: level
    }
    return next
  }

  // VIEW with a new streams array where stream INDEX has volume VOLUME.
  function streamVolumeTick(view, index, volume) {
    var next = levelTick(view, view.output.level)
    next.streams = view.streams.map(function (s, i) {
      return {
        key: s.key,
        label: s.label,
        volume: i === index ? volume : s.volume,
        muted: s.muted,
        current: s.current
      }
    })
    return next
  }

  // VIEW with the cursor set to ACTIVE, SECTION and INDEX.
  function cursorTick(view, active, section, index) {
    var next = levelTick(view, view.output.level)
    next.cursor = {
      active: active,
      section: section,
      index: index
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
    var output = t.findChild(full, "outputSection")
    var rows = t.findChildren(output, "deviceRow")
    t.equal(rows.length, 3, "all three outputs are listed, unplugged included")
    t.check(rows[0].active && !rows[1].active, "the active output is marked")
    rows[2].activate()
    rows[1].activate()
    t.equal(JSON.stringify(actions), JSON.stringify([["outputDevice", 1]]), "only the available device is chosen")
    var hoversBefore = actions.length
    rows[2].entered()
    t.equal(actions.length, hoversBefore, "hovering an unplugged device doesn't move the cursor")
    rows[1].entered()
    t.equal(JSON.stringify(actions[actions.length - 1]), JSON.stringify(["hover",
      {
        section: "output",
        index: 1
      }
    ]), "hovering an available device moves the cursor")
    t.findChild(output, "channelSlider").rightClicked()
    t.equal(actions[actions.length - 1][0], "outputMute", "right-click on the output slider mutes output")
    var sources = t.findChild(full, "sourcesSection")
    var streamSlider = t.findChildren(sources, "streamSlider")[0]
    t.equal(streamSlider.maximum, 1.5, "streams go to 150%")
    var header = t.findChild(full, "audioHeader")
    t.check(header !== null && header.hintTip.text === "Mute", "the mute-all switch explains itself (stock's toggleHint)")
    t.check(t.findChild(full, "nowPlaying").visible, "now playing shows with a player")
    t.check(!t.findChild(bare, "nowPlaying").visible, "now playing hides without one")
    t.check(!t.findChild(bare, "sourcesSection").visible, "sources hide without streams")
    t.check(!t.findChild(bare, "inputSection").visible, "input hides without a source")
    t.check(t.findChild(t.findChild(bare, "outputSection"), "emptyText").visible, "a missing output says so")
    var edge = rightEdge(full)
    var trailing = [t.findChild(full, "headerTrailing"), t.findChild(output, "levelText"), t.findChild(output, "channelSlider"), rows[0], streamSlider]
    for (var i = 0; i < trailing.length; i++)
      t.check(Math.abs(rightEdge(trailing[i]) - edge) < 0.5, "trailing element " + i + " ends on the content edge")
    // A level tick rebuilds the view object but reuses the row arrays, as
    // Panel.audioView does; the row delegates must survive it, or a slider
    // drag or click in progress would be lost.
    var deviceRowsBefore = t.findChildren(output, "deviceRow")
    var streamRowsBefore = t.findChildren(sources, "streamRow")
    full.view = levelTick(full.view, 0.9)
    t.step(50, function () {
      var deviceRowsAfter = t.findChildren(output, "deviceRow")
      var streamRowsAfter = t.findChildren(sources, "streamRow")
      t.equal(t.findChild(output, "channelSlider").level, 0.9, "the level tick reaches the output filament")
      t.equal(deviceRowsAfter.length, deviceRowsBefore.length, "a level tick keeps the device rows")
      t.equal(streamRowsAfter.length, streamRowsBefore.length, "a level tick keeps the stream rows")
      for (var j = 0; j < deviceRowsBefore.length; j++)
        t.check(deviceRowsAfter[j] === deviceRowsBefore[j], "device row " + j + " is the same delegate after a level tick")
      for (var k = 0; k < streamRowsBefore.length; k++)
        t.check(streamRowsAfter[k] === streamRowsBefore[k], "stream row " + k + " is the same delegate after a level tick")
      // Dragging a stream slider writes the volume back, which arrives as
      // a new streams array; the rows (and the slider's drag) must survive.
      full.view = streamVolumeTick(full.view, 0, 0.9)
      t.step(50, function () {
        var streamRowsMoved = t.findChildren(sources, "streamRow")
        t.equal(t.findChildren(sources, "streamSlider")[0].value, 0.9, "the new stream volume reaches its slider")
        for (var m = 0; m < streamRowsBefore.length; m++)
          t.check(streamRowsMoved[m] === streamRowsBefore[m], "stream row " + m + " is the same delegate after a volume change")
        // The cursor outline is the keyboard's: Panel passes an inactive
        // cursor while the mouse is in use, and then nothing is outlined.
        t.equal(litOutlines(full), 0, "no outline without an active cursor")
        full.view = cursorTick(full.view, true, "output", 1)
        t.step(50, function () {
          t.equal(litOutlines(full), 1, "an active cursor outlines exactly one row")
          full.view = cursorTick(full.view, false, "output", 1)
          t.step(50, function () {
            t.equal(litOutlines(full), 0, "the outline goes once the cursor is inactive")
            t.done()
          })
        })
      })
    })
  })
}
