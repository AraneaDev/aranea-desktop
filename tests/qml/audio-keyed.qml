// The Aranea audio view's Filament click rules, in a real window with real
// pointer events: the pending default's row shows as active and pulses;
// device and stream actions carry the node id and a keyed action whose row
// changed underneath (a re-sort) is refused, including a stream slider
// drag that started on a stream which then moved; device keys, stream
// keys, a section and Now playing showing or hiding stamp the layout (an
// equal list rebuilt does not); the mute switch, the channel slider, a
// stream's mute glyph and slider and the transport buttons refuse clicks
// within 300 ms of a stamp and accept them after; a row sliding under a
// still pointer emits no hover and takes no click; and the progress bar is
// lit as the strand gradient (mint to violet).
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.audio" as Audio
import "plugins/araneadev.shared" as Shared

ShellRoot {
  QmlTest {
    id: t
  }

  // Actions reported by full, as [name, arg], in emission order.
  property var actions: []
  // The layout stamp a step compares against.
  property real stampBefore: 0
  // The pointer's resting point for the still-pointer checks.
  property var stillPoint: null

  // Synthesizes pointer events (TestCase's mouse helpers), never run as a
  // test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // An output device row: KEY and LABEL.
  function device(key, label) {
    return {
      key: key,
      label: label,
      glyph: "",
      detail: "",
      available: true
    }
  }

  // A stream row: KEY, LABEL and VOLUME.
  function stream(key, label, volume) {
    return {
      key: key,
      label: label,
      volume: volume,
      muted: false,
      current: false
    }
  }

  // The output devices, the switch to "2" pending.
  readonly property var outputRows: [device("1", "ALC236 Analog"), device("2", "LG ULTRAGEAR"), device("3", "WH-1000XM4")]
  // The default output as the view shows it: the switch to "2" pending.
  property var outputDefault: ({
      key: "2",
      busy: true
    })
  // The streams, in their first order.
  readonly property var streamRows: [stream("7", "Spotify", 0.8), stream("8", "Firefox", 0.6)]

  // A view with OUTPUTS, STREAMS, INPUT shown or not and Now playing
  // shown or not.
  function viewOf(outputs, streams, input, playing) {
    return {
      glyph: "",
      mood: "",
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
        volume: 0.5,
        muted: false,
        level: 0
      },
      outputDevices: outputs,
      outputDefault: outputDefault,
      inputDefault: {
        key: "9",
        busy: false
      },
      inputVisible: input,
      input: {
        present: input,
        volume: 0.5,
        muted: false,
        level: 0
      },
      inputDevices: input ? [device("9", "Mic")] : [],
      streams: streams,
      nowPlaying: {
        visible: playing,
        player: "Spotify",
        title: "Midnight City",
        artist: "M83",
        album: "",
        progress: playing ? 0.5 : -1,
        playing: true,
        canPrevious: true,
        canNext: true
      }
    }
  }

  // Actions other than hover.
  function nonHover() {
    return actions.filter(function (a) {
      return a[0] !== "hover"
    })
  }

  // Actions named NAME.
  function named(name) {
    return actions.filter(function (a) {
      return a[0] === name
    })
  }

  // Whether an action NAME with ARG (compared as JSON) was reported.
  function reported(name, arg) {
    var want = JSON.stringify([name, arg])
    return actions.some(function (a) {
      return JSON.stringify(a) === want
    })
  }

  // Output's device rows, in order.
  function outputDeviceRows() {
    return t.findChildren(t.findChild(full, "outputSection"), "deviceRow")
  }

  // The stream rows' sliders, in order.
  function streamSliders() {
    return t.findChildren(t.findChild(full, "sourcesSection"), "streamSlider")
  }

  // The stream rows' mute glyph areas, in order.
  function streamMutes() {
    return t.findChildren(t.findChild(full, "sourcesSection"), "streamMute")
  }

  // Clicks every gated control once: the mute switch, the output slider,
  // stream 0's mute glyph and slider, and play/pause.
  function clickControls() {
    pointer.mouseClick(t.findChild(full, "muteSwitch"))
    var slider = t.findChild(t.findChild(full, "outputSection"), "channelSlider")
    pointer.mouseClick(slider, slider.width / 2, slider.height / 2)
    pointer.mouseClick(streamMutes()[0])
    var ss = streamSliders()[0]
    pointer.mouseClick(ss, ss.width / 2, ss.height / 2)
    pointer.mouseClick(t.findChild(full, "playPauseButton"))
  }

  // Turns the wheel one notch up over the output slider and stream 0's
  // slider.
  function wheelSliders() {
    var slider = t.findChild(t.findChild(full, "outputSection"), "channelSlider")
    pointer.mouseWheel(slider, slider.width / 2, slider.height / 2, 0, 120)
    var ss = streamSliders()[0]
    pointer.mouseWheel(ss, ss.width / 2, ss.height / 2, 0, 120)
  }

  // Runs STEPS ([delay, fn] pairs) one after another, then finishes.
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
    implicitWidth: 380
    implicitHeight: 760
    visible: true

    Audio.AudioDropdown {
      id: full
      width: 360
      view: viewOf(outputRows, streamRows, true, true)
      onAction: function (name, arg) {
        actions.push([name, arg])
      }
    }
  }

  Component.onCompleted: run([[400, function () {
        // ---------- Pending default ----------
        var rows = outputDeviceRows()
        t.check(rows[1].active && rows[1].busy, "the pending default's row shows as active and pulses")
        t.check(!rows[0].busy && !rows[0].active && !rows[2].busy, "no other row is active or pulses")

        // A pending change, as Panel sends it: the same row array, a new
        // default. The row delegates must survive it.
        var created = rows.map(function (row) {
          return row.createdAt
        })
        var sameRows = full.view.outputDevices
        outputDefault = {
          key: "3",
          busy: true
        }
        full.view = viewOf(sameRows, streamRows, true, true)
        var after = outputDeviceRows()
        t.check(after.length === 3 && after.every(function (row, i) {
          return row === rows[i] && row.createdAt === created[i]
        }), "a pending change keeps the row delegates")
        t.check(after[2].active && after[2].busy && !after[1].active && !after[1].busy, "and moves the active pulse to the new row")
        outputDefault = {
          key: "3",
          busy: false
        }
        full.view = viewOf(sameRows, streamRows, true, true)
        t.check(outputDeviceRows()[2] === rows[2] && rows[2].active && !rows[2].busy, "the echo stops the pulse on the same delegate")
        outputDefault = {
          key: "2",
          busy: true
        }
        full.view = viewOf(outputRows, streamRows, true, true)

        // ---------- Gradient progress bar ----------
        var fill = t.findChild(full, "progressFill")
        t.check(fill !== null && fill.visible && fill.width > 0, "the progress bar draws its played part")
        var stops = fill && fill.gradient ? fill.gradient.stops : []
        t.equal(stops.length, 2, "the played part is a two-stop gradient")
        t.check(stops.length === 2 && Qt.colorEqual(stops[0].color, Shared.DesignTokens.accent) && Qt.colorEqual(stops[1].color, Shared.DesignTokens.strandEnd), "it runs mint to violet, as the strand")
        t.equal(fill.gradient.orientation, Gradient.Horizontal, "along its length")
        t.equal(fill.height, t.findChild(full, "progressBar").height, "and keeps the bar's height")

        // ---------- Keyed device actions ----------
        actions = []
        pointer.mouseClick(rows[2], 60, rows[2].height / 2)
        t.check(reported("outputDevice", {
          index: 2,
          key: "3"
        }), "a settled click reports the device with its key")

        // A re-sort: "1" moves from row 0 to row 2.
        actions = []
        stampBefore = full.layoutChangedAt
        full.view = viewOf(outputRows.slice().reverse(), streamRows, true, true)
        t.check(full.layoutChangedAt > stampBefore, "a re-sort of the devices stamps the layout")
        full.keyedAction("outputDevice", full.view.outputDevices, 0, "1")
        t.equal(nonHover().length, 0, "a keyed device action whose row changed underneath is refused")
        full.keyedAction("outputDevice", full.view.outputDevices, 2, "1")
        t.check(reported("outputDevice", {
          index: 2,
          key: "1"
        }), "the same key at its new row is accepted")
        actions = []
        pointer.mouseClick(outputDeviceRows()[0], 60, outputDeviceRows()[0].height / 2)
        t.equal(nonHover().length, 0, "a click right after the re-sort is refused")
      }], [350, function () {
        // ---------- Keyed stream drag across a re-sort ----------
        actions = []
        var ss = streamSliders()[0]
        pointer.mousePress(ss, ss.width / 4, ss.height / 2)
        pointer.mouseMove(ss, ss.width / 3, ss.height / 2, -1, Qt.LeftButton)
        var moves = named("streamVolume")
        t.check(moves.length > 0 && moves.every(function (a) {
          return a[1].index === 0 && a[1].key === "7"
        }), "dragging stream 0 reports its volume keyed by its node id")
        // The streams re-sort mid-drag: row 0 now holds Firefox ("8").
        actions = []
        stampBefore = full.layoutChangedAt
        full.view = viewOf(outputRows.slice().reverse(), streamRows.slice().reverse(), true, true)
        t.check(full.layoutChangedAt > stampBefore, "a re-sort of the streams stamps the layout")
        t.check(streamSliders()[0] === ss && ss.dragging, "the drag survives the re-sort")
        pointer.mouseMove(ss, ss.width / 2, ss.height / 2, -1, Qt.LeftButton)
        pointer.mouseRelease(ss, ss.width / 2, ss.height / 2)
        t.equal(named("streamVolume").length, 0, "the drag never moves the stream that slid into its row")
        full.keyedAction("streamMute", full.view.streams, 0, "7")
        t.equal(named("streamMute").length, 0, "a keyed stream mute whose row changed underneath is refused")
        full.keyedAction("streamMute", full.view.streams, 1, "7")
        t.check(reported("streamMute", {
          index: 1,
          key: "7"
        }), "the same stream at its new row is accepted")

        // ---------- Stamps ----------
        stampBefore = full.layoutChangedAt
        full.view = viewOf(outputRows.slice().reverse().map(function (r) {
          return Object.assign({}, r)
        }), streamRows.slice().reverse().map(function (r) {
          return Object.assign({}, r)
        }), true, true)
        t.equal(full.layoutChangedAt, stampBefore, "equal lists rebuilt do not stamp")
      }], [20, function () {
        full.view = viewOf(outputRows.slice().reverse(), streamRows.slice().reverse(), true, false)
        t.check(full.layoutChangedAt > stampBefore, "Now playing hiding stamps")
        stampBefore = full.layoutChangedAt
      }], [20, function () {
        full.view = viewOf(outputRows.slice().reverse(), streamRows.slice().reverse(), false, false)
        t.check(full.layoutChangedAt > stampBefore, "Input hiding stamps")
        stampBefore = full.layoutChangedAt
      }], [20, function () {
        full.view = viewOf(outputRows.slice().reverse(), [], false, false)
        t.check(full.layoutChangedAt > stampBefore, "Sources hiding stamps")
        stampBefore = full.layoutChangedAt
      }], [20, function () {
        full.view = viewOf(outputRows, streamRows, true, true)
        t.check(full.layoutChangedAt > stampBefore, "everything showing again stamps")
      }], [350, function () {
        // ---------- Settle window after a stamp ----------
        actions = []
        full.noteLayoutChange()
        clickControls()
        t.equal(nonHover().length, 0, "clicks right after a stamp are refused (switch, sliders, stream mute, play/pause)")
        wheelSliders()
        t.equal(nonHover().length, 0, "wheel steps right after a stamp are refused (output and stream sliders)")
      }], [60, function () {
        clickControls()
        t.equal(nonHover().length, 0, "and still refused inside the settle window")
      }], [350, function () {
        actions = []
        wheelSliders()
        t.check(named("outputVolume").length === 1, "a settled wheel step moves the output slider")
        t.check(named("streamVolume").length === 1 && named("streamVolume")[0][1].key === "7", "a settled wheel step moves the stream, keyed")
        actions = []
        clickControls()
        t.check(reported("toggleAll", null), "a settled mute switch click toggles")
        t.check(named("outputVolume").length > 0, "a settled output slider click moves it")
        t.check(reported("streamMute", {
          index: 0,
          key: "7"
        }), "a settled stream mute click is keyed")
        t.check(named("streamVolume").length > 0 && named("streamVolume").every(function (a) {
          return a[1].key === "7"
        }), "a settled stream slider click is keyed")
        t.check(reported("playPause", null), "a settled play/pause click plays")

        // ---------- A still pointer ----------
        full.disarmPointer()
        var ss1 = streamSliders()[1]
        stillPoint = ss1.mapToItem(full, ss1.width / 2, ss1.height / 2)
        pointer.mouseMove(full, stillPoint.x, stillPoint.y)
      }], [80, function () {
        pointer.mouseMove(full, stillPoint.x + 4, stillPoint.y)
      }], [400, function () {
        t.check(actions.some(function (a) {
          return a[0] === "hover" && a[1].section === "streams" && a[1].index === 1
        }), "a real move over a stream reports hover")
        actions = []
        // The first output leaves: everything below slides up under the
        // still pointer.
        full.view = viewOf(outputRows.slice(1), streamRows, true, true)
      }], [60, function () {
        pointer.mouseMove(full, stillPoint.x + 4, stillPoint.y)
        t.equal(actions.filter(function (a) {
          return a[0] === "hover"
        }).length, 0, "a row sliding under a still pointer emits no hover")
        pointer.mouseClick(full, stillPoint.x + 4, stillPoint.y)
        t.equal(nonHover().length, 0, "nor takes a click inside the settle window")
      }]])
}
