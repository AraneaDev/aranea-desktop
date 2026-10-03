// The Aranea audio dropdown's view: header, Output, Input, Sources and Now
// playing, drawn from one plain view object (Panel.audioView) and
// reporting every user action through a single action signal. No
// Pipewire here, so tests drive it with fixtures.
//
// Anything that moves rows or controls under a still pointer without the
// pointer moving (a device or stream joining, leaving or re-sorting, a
// section or a channel's slider showing or hiding, Now playing showing or
// hiding) stamps layoutChangedAt, which the rows, sliders, switch and
// transport buttons read through pointerGate: a click within 300 ms of it
// is ignored unless the pointer has really moved there since. Device and
// stream actions carry the row's key (its node id) and are never sent
// when the row at that index holds another key.
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Column {
  id: dropdown

  // View state built by Panel.audioView (see AudioLogic.js for nowPlaying).
  property var view: ({})
  // Cursor object from the view, or a neutral one.
  readonly property var cursor: view && view.cursor ? view.cursor : ({
      active: false,
      section: "",
      index: -1
    })
  // Filters synthetic hover from rows and controls moving under a still
  // pointer (e.g. a device list changing underneath the cursor).
  readonly property alias pointerGate: gate
  // When the layout last shifted under the pointer (Date.now()), 0 for
  // never; see noteLayoutChange.
  property real layoutChangedAt: 0
  // The output device keys joined, so an equal list rebuilt by the host
  // does not stamp the layout.
  readonly property string outputKeys: dropdown.joinKeys(dropdown.view.outputDevices)
  // The input device keys joined (see outputKeys).
  readonly property string inputKeys: dropdown.joinKeys(dropdown.view.inputDevices)
  // The stream keys joined (see outputKeys).
  readonly property string streamKeys: dropdown.joinKeys(dropdown.view.streams)
  // Whether the Output and Input sliders show; each moves what is below.
  readonly property string channelsShown: String(!!(dropdown.view.output && dropdown.view.output.present)) + String(!!(dropdown.view.input && dropdown.view.input.present))

  // Stamps layoutChangedAt: something moved rows without the pointer.
  function noteLayoutChange() {
    dropdown.layoutChangedAt = Date.now()
  }

  // ROWS' keys joined by newlines, "" for none.
  function joinKeys(rows) {
    return (rows || []).map(function (r) {
      return r && r.key !== undefined ? String(r.key) : ""
    }).join("\n")
  }

  // Reports NAME for row INDEX of ROWS holding KEY, with ARG's fields
  // added, refused when that row no longer carries KEY (the list changed
  // underneath).
  function keyedAction(name, rows, index, key, extra) {
    var row = (rows || [])[index]
    if (!row || String(row.key) !== key)
      return
    var arg = {
      index: index,
      key: key
    }
    for (var field in extra || {})
      arg[field] = extra[field]
    dropdown.action(name, arg)
  }

  // Resets the pointer gate; called after every keyboard-driven move so a
  // stale pointer sample never steals the cursor back.
  function disarmPointer() {
    gate.reset()
  }

  // Emitted for every user action, NAME with its ARG:
  //   toggleAll (none): mute or unmute every channel;
  //   outputVolume / inputVolume (volume 0..1.5): set a channel's volume;
  //   outputMute / inputMute (none): toggle a channel's mute;
  //   outputDevice / inputDevice ({index, key}): make that device the
  //     default;
  //   streamVolume ({index, key, value}) / streamMute ({index, key}): one
  //     app stream;
  //   device and stream actions carry the row's key (the node id) as the
  //   view held it, and are never sent when the row's key changed
  //   underneath;
  //   previous / playPause / next (none): the Now playing controls;
  //   hover ({section, index}): the pointer entered a row or control.
  signal action(string name, var arg)

  // Cursor index for SECTION: the view's index there, else -2 (none).
  function cursorIn(section) {
    return cursor.active && cursor.section === section ? cursor.index : -2
  }

  spacing: Style.space(14)
  onOutputKeysChanged: dropdown.noteLayoutChange()
  onInputKeysChanged: dropdown.noteLayoutChange()
  onStreamKeysChanged: dropdown.noteLayoutChange()
  onChannelsShownChanged: dropdown.noteLayoutChange()

  AudioHeader {
    width: parent.width
    glyph: dropdown.view.glyph || ""
    mood: dropdown.view.mood || ""
    anyAudible: !!dropdown.view.anyAudible
    hint: dropdown.view.toggleHint || ""
    hasCursor: !!dropdown.view.headerCursor
    pointerGate: dropdown.pointerGate
    onToggleAll: dropdown.action("toggleAll", null)
    onEntered: dropdown.action("hover", {
      section: "header",
      index: -1
    })
  }
  Rectangle {
    width: parent.width
    height: Math.max(1, Style.spacing.hairline)
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
    visible: outputSection.visible
  }
  AudioChannelSection {
    id: outputSection
    objectName: "outputSection"
    width: parent.width
    caption: "OUTPUT"
    emptyText: "No output device"
    channel: dropdown.view.output || ({
        present: false,
        volume: 0,
        muted: false,
        level: 0
      })
    devices: dropdown.view.outputDevices || []
    shownKey: dropdown.view.outputDefault ? String(dropdown.view.outputDefault.key || "") : ""
    shownBusy: !!(dropdown.view.outputDefault && dropdown.view.outputDefault.busy)
    cursor: dropdown.cursorIn("output")
    pointerGate: dropdown.pointerGate
    onVolumeMoved: function (value) {
      dropdown.action("outputVolume", value)
    }
    onMuteToggled: dropdown.action("outputMute", null)
    onDeviceChosen: function (index, key) {
      dropdown.keyedAction("outputDevice", outputSection.devices, index, key)
    }
    onRowHovered: function (index) {
      dropdown.action("hover", {
        section: "output",
        index: index
      })
    }
  }
  Rectangle {
    width: parent.width
    height: Math.max(1, Style.spacing.hairline)
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
    visible: inputSection.visible
  }
  AudioChannelSection {
    id: inputSection
    objectName: "inputSection"
    width: parent.width
    visible: !!dropdown.view.inputVisible
    // Showing or hiding moves everything below it.
    onVisibleChanged: dropdown.noteLayoutChange()
    caption: "INPUT"
    emptyText: "No input device"
    channel: dropdown.view.input || ({
        present: false,
        volume: 0,
        muted: false,
        level: 0
      })
    devices: dropdown.view.inputDevices || []
    shownKey: dropdown.view.inputDefault ? String(dropdown.view.inputDefault.key || "") : ""
    shownBusy: !!(dropdown.view.inputDefault && dropdown.view.inputDefault.busy)
    cursor: dropdown.cursorIn("input")
    pointerGate: dropdown.pointerGate
    onVolumeMoved: function (value) {
      dropdown.action("inputVolume", value)
    }
    onMuteToggled: dropdown.action("inputMute", null)
    onDeviceChosen: function (index, key) {
      dropdown.keyedAction("inputDevice", inputSection.devices, index, key)
    }
    onRowHovered: function (index) {
      dropdown.action("hover", {
        section: "input",
        index: index
      })
    }
  }
  Rectangle {
    width: parent.width
    height: Math.max(1, Style.spacing.hairline)
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
    visible: sourcesSection.visible
  }
  AudioSourcesSection {
    id: sourcesSection
    width: parent.width
    streams: dropdown.view.streams || []
    cursor: Math.max(-1, dropdown.cursorIn("streams"))
    pointerGate: dropdown.pointerGate
    // Showing or hiding moves everything below it.
    onVisibleChanged: dropdown.noteLayoutChange()
    onVolumeMoved: function (index, key, value) {
      dropdown.keyedAction("streamVolume", sourcesSection.streams, index, key, {
        value: value
      })
    }
    onMuteToggled: function (index, key) {
      dropdown.keyedAction("streamMute", sourcesSection.streams, index, key)
    }
    onRowHovered: function (index) {
      dropdown.action("hover", {
        section: "streams",
        index: index
      })
    }
  }
  Rectangle {
    width: parent.width
    height: Math.max(1, Style.spacing.hairline)
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
    visible: nowPlayingStrip.visible
  }
  AudioNowPlaying {
    id: nowPlayingStrip
    width: parent.width
    info: dropdown.view.nowPlaying || ({
        visible: false,
        player: "",
        title: "",
        artist: "",
        album: "",
        progress: -1,
        playing: false,
        canPrevious: false,
        canNext: false
      })
    hasCursor: dropdown.cursorIn("nowplaying") >= 0
    pointerGate: dropdown.pointerGate
    // Showing or hiding moves the key hint below it.
    onVisibleChanged: dropdown.noteLayoutChange()
    onPreviousRequested: dropdown.action("previous", null)
    onPlayPauseRequested: dropdown.action("playPause", null)
    onNextRequested: dropdown.action("next", null)
    onEntered: dropdown.action("hover", {
      section: "nowplaying",
      index: 0
    })
  }
  Text {
    width: parent.width
    text: "↑↓ move · ←→ adjust · enter select · m mute · tab next"
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.3)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  PointerMoveGate {
    id: gate
    // The dropdown's last layout shift, for the controls' clickSettled().
    property real layoutChangedAt: dropdown.layoutChangedAt

    referenceItem: dropdown
  }
}
