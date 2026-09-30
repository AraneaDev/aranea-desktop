// The Aranea audio dropdown's view: header, Output, Input, Sources and Now
// playing, drawn from one plain view object (Panel.audioView) and
// reporting every user action through a single action signal. No
// Pipewire here, so tests drive it with fixtures.
import QtQuick
import qs.Commons
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

  // Emitted for every user action; see the plan's action list.
  signal action(string name, var arg)

  // Cursor index for SECTION: the view's index there, else -2 (none).
  function cursorIn(section) {
    return cursor.active && cursor.section === section ? cursor.index : -2
  }

  spacing: Style.space(14)

  AudioHeader {
    width: parent.width
    glyph: dropdown.view.glyph || ""
    mood: dropdown.view.mood || ""
    anyAudible: !!dropdown.view.anyAudible
    hasCursor: !!dropdown.view.headerCursor
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
        present: false
      })
    devices: dropdown.view.outputDevices || []
    cursor: dropdown.cursorIn("output")
    onVolumeMoved: function (value) {
      dropdown.action("outputVolume", value)
    }
    onMuteToggled: dropdown.action("outputMute", null)
    onDeviceChosen: function (index) {
      dropdown.action("outputDevice", index)
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
    caption: "INPUT"
    emptyText: "No input device"
    channel: dropdown.view.input || ({
        present: false
      })
    devices: dropdown.view.inputDevices || []
    cursor: dropdown.cursorIn("input")
    onVolumeMoved: function (value) {
      dropdown.action("inputVolume", value)
    }
    onMuteToggled: dropdown.action("inputMute", null)
    onDeviceChosen: function (index) {
      dropdown.action("inputDevice", index)
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
    onVolumeMoved: function (index, value) {
      dropdown.action("streamVolume", {
        index: index,
        value: value
      })
    }
    onMuteToggled: function (index) {
      dropdown.action("streamMute", index)
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
        visible: false
      })
    hasCursor: dropdown.cursorIn("nowplaying") >= 0
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
}
