// Aranea audio (araneadev.audio, cloned from omarchy.audio): the bar
// volume icon and its dropdown. Stock logic; the Aranea view replaces
// the stock one. Added: the showcase IPC method's display-only stand-ins
// for README captures.
import QtQuick
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Ui
import qs.Commons
import "Model.js" as Model
import "AudioLogic.js" as AudioLogic
import "AudioBridge.js" as AudioBridge
import "../araneadev.shared/ShowcaseLogic.js" as Showcase
import "../araneadev.shared" as Aranea

Panel {
  id: root
  moduleName: "omarchy.audio"
  ipcTarget: "omarchy.audio"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the showcase method below.
  manageIpc: false

  IpcHandler {
    target: "omarchy.audio"

    function open() {
      root.open()
    }
    function close() {
      root.close()
    }
    function show() {
      root.open()
    }
    function hide() {
      root.close()
    }
    function toggle() {
      root.toggle()
    }
    // Screenshot stand-ins (scripts/capture-screenshots): SHOWCASEJSON, a
    // JSON object (AudioLogic.parseShowcase), relabels the output, input
    // and stream rows and puts a made-up track in Now playing until the
    // dropdown closes; while it is closed the answer is "closed" and
    // nothing is set. Display only: PipeWire and the players are never
    // touched, and the transport controls are refused meanwhile.
    function showcase(showcaseJson: string): string {
      var call = AudioLogic.showcaseCall(root.opened, showcaseJson)
      if (call.showcase !== null)
        root.audioShowcase = call.showcase
      return call.answer
    }
  }

  // Stand-ins for README screenshots (the showcase IPC method); null
  // outside a capture, and cleared whenever the dropdown opens or closes.
  property var audioShowcase: null

  // The system default output device.
  readonly property var sink: Pipewire.defaultAudioSink
  // The system default input device.
  readonly property var source: Pipewire.defaultAudioSource
  // All Pipewire nodes, or [] before the service is ready.
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  // All known MPRIS media players.
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  // Omarchy's media service, when the bar exposes one.
  // qmllint disable missing-property
  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("omarchy.media")
  // qmllint enable missing-property
  // The media service's currently active player, if any.
  readonly property var activeMediaPlayer: mediaService ? mediaService.activePlayer : null

  // Persistent default owner published by the keep-loaded audio service.
  property var defaultOwner: AudioBridge.current()
  // Owner currently leased by this open panel.
  property var leasedOwner: null
  // Output pending projection, shared with search and other panels.
  readonly property var outputPending: defaultOwner ? defaultOwner.outputPending : AudioLogic.defaultIdle()
  // Input pending projection.
  readonly property var inputPending: defaultOwner ? defaultOwner.inputPending : AudioLogic.defaultIdle()
  // Observed output identity.
  readonly property string sinkKey: AudioLogic.deviceKey(sink)
  // Observed input identity.
  readonly property string sourceKey: AudioLogic.deviceKey(source)
  // Existing optimistic output presentation from the shared owner.
  readonly property var outputShown: AudioLogic.defaultView(outputPending, sinkKey)
  // Existing optimistic input presentation from the shared owner.
  readonly property var inputShown: AudioLogic.defaultView(inputPending, sourceKey)
  // Reacquire an owner after plugin load/reload and balance the panel lease.
  function syncDefaultOwner(): void {
    defaultOwner = AudioBridge.current()
    if (leasedOwner && (leasedOwner !== defaultOwner || !opened)) {
      leasedOwner.panelClosed()
      leasedOwner = null
    }
    if (opened && defaultOwner && leasedOwner !== defaultOwner) {
      defaultOwner.panelOpened()
      leasedOwner = defaultOwner
    }
  }
  Component.onDestruction: if (leasedOwner)
    leasedOwner.panelClosed()
  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.syncDefaultOwner()
  }

  // Smoothed live levels behind the Output and Input filament glow.
  property real outputSignal: 0
  // (see above)
  property real inputSignal: 0
  // dbusName of the player Now playing showed last.
  property string lastPlayerKey: ""
  // The player Now playing follows: Omarchy's media service first.
  readonly property var nowPlayingPlayer: activeMediaPlayer || AudioLogic.pickPlayer(mprisPlayers, lastPlayerKey)
  // What the Now playing strip shows: the stand-in track while showcasing.
  readonly property var nowPlaying: AudioLogic.showcaseNowPlaying(audioShowcase, AudioLogic.nowPlayingState(nowPlayingPlayer))
  // The player the transport controls act on: none while showcasing, so
  // they never act on the real player behind a stand-in track.
  readonly property var transportPlayer: audioShowcase ? null : nowPlayingPlayer

  // Remember the followed player, so Now playing stays on it once it pauses.
  onNowPlayingPlayerChanged: if (nowPlayingPlayer)
    lastPlayerKey = String(nowPlayingPlayer.dbusName || "")

  // Fresh candidate output devices from the persistent owner.
  readonly property var candidateSinks: defaultOwner ? defaultOwner.candidateSinks : []
  // Fresh candidate input devices from the persistent owner.
  readonly property var candidateSources: defaultOwner ? defaultOwner.candidateSources : []

  // Per-app playback streams, excluding the speaker-tuning's own output.
  readonly property var candidateStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isStream || !isPlaybackStream(n))
        continue
      // A tuning's output is a playback stream too, but it is the processing
      // itself rather than an application, so it does not belong in the list.
      if (String(n.name || "").indexOf("omarchy_speaker_tuning") === 0)
        continue
      list.push(n)
    }
    return list
  }

  // Identify true playback streams without reading node.properties here:
  // PwNode.properties is invalid until the node is bound, and reading it while
  // capture streams are appearing (for example, when Voxtype starts recording)
  // can destabilize Quickshell's Pipewire service. Quickshell versions differ
  // in how `type` is exposed (media.class, enum name, or numeric enum), but
  // playback streams consistently accept audio input from clients and publish
  // `isSink: true`; capture streams publish as stream sources.
  function isPlaybackStream(node) {
    return Model.isPlaybackStream(node)
  }

  // Whether node is an audio-capable source, delegating to Model.js.
  function isAudioSource(node) {
    return Model.isAudioSource(node)
  }

  // Shared output presentation including its transient cached fallback.
  readonly property var audioSinks: defaultOwner ? defaultOwner.audioSinks : []
  // Shared input presentation including its transient cached fallback.
  readonly property var audioSources: defaultOwner ? defaultOwner.audioSources : []
  // Shared unavailable outputs, never selectable.
  readonly property var unpluggedSinks: defaultOwner ? defaultOwner.unpluggedSinks : []

  // Candidate streams that actually carry an audio channel.
  readonly property var audioStreams: {
    var list = []
    for (var i = 0; i < candidateStreams.length; i++)
      if (candidateStreams[i].audio)
        list.push(candidateStreams[i])
    return list
  }

  // Feed Repeaters with panel-local snapshots instead of the live PipeWire
  // model. PipeWire can remove nodes while Quickshell is dispatching the
  // removal signal; rebuilding a Repeater from that signal path has crashed
  // in Quickshell's PipeWire service. The snapshot timer lets that mutation
  // settle first, and closed panels keep their repeaters detached entirely.
  property var displayAudioSinks: []
  // Display snapshot of the current input devices.
  property var displayAudioSources: []
  // Display snapshot of the per-app playback streams.
  property var displayAudioStreams: []
  // Display snapshot of the unplugged outputs (see displayAudioSinks).
  property var displayUnpluggedSinks: []

  // A DSP sink -- a speaker tuning, or EasyEffects -- can be the selected output
  // without being where loudness lives: changing its volume alters the level going
  // *into* the processing, so the slider would move while the speakers did not,
  // and on a chain with a limiter it would change the tone as well.
  //
  // omarchy-audio-output-sink resolves the *current* default output through any
  // such sink to the physical one, which is the same definition the volume keys
  // and the output switcher use. Resolving the default (rather than "whatever a
  // tuning fronts") is what keeps this correct when headphones or HDMI are
  // selected while a tuning still exists.
  property string volumeSinkName: ""

  // Carry sub-notch touchpad deltas between wheel events.
  property real wheelAccumulator: 0

  // Resolves through any DSP/tuning sink to the physical output the volume keys act on.
  readonly property var volumeSink: {
    if (volumeSinkName === "" || !sink)
      return sink
    if (volumeSinkName === String(sink.name))
      return sink
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream && String(n.name) === volumeSinkName && n.audio)
        return n
    }
    return sink
  }

  // Re-resolve whenever the selected output changes; the timer below is only a
  // safety net for the tuning being applied or removed underneath us.
  // A new default output also settles a pending switch to it.
  onSinkChanged: resolveVolumeSink()

  // Kicks off omarchy-audio-output-sink to refresh volumeSinkName asynchronously.
  function resolveVolumeSink() {
    if (!volumeSinkProc.running)
      volumeSinkProc.running = true
  }

  // The resolved sink's output volume, 0..1.
  readonly property real outputVolume: volumeSink && volumeSink.audio ? volumeSink.audio.volume : 0
  // Whether the resolved output sink is muted.
  readonly property bool outputMuted: volumeSink && volumeSink.audio ? volumeSink.audio.muted : false
  // The default input device's volume, 0..1.
  readonly property real inputVolume: source && source.audio ? source.audio.volume : 0
  // Whether the default input device is muted.
  readonly property bool inputMuted: source && source.audio ? source.audio.muted : false

  // Single cursor model shared by keyboard and mouse. Sections:
  //   "output"  — output slider + sink device list
  //   "input"   — input slider + source device list
  //   "streams" — per-app playback streams
  //   "nowplaying" - the Now playing strip (a single row)
  // selectedIndex semantics within a section:
  //   -1            → on the slider row (h/l adjusts volume, m/Enter mute)
  //   0..N-1        → on the Nth device/stream row
  // Visuals derive from hasCursor/current via CursorSurface, never
  // from containsMouse — that's what keeps the highlight unique across
  // keyboard + mouse like wifi does.
  property string focusSection: "output"
  // -1 for the slider row, else the index of the focused device/stream row.
  property int selectedIndex: -1
  // True once the keyboard or mouse has given a row focus.
  property bool cursorActive: false
  // True while the keyboard drives the cursor; any pointer action clears it.
  // The view outlines the cursor only then, so the mouse never shows one.
  property bool keyboardCursor: false

  // "header" is a virtual section for the hero output mute toggle; it sits
  // above the output section so the speaker can be muted from the keyboard.
  readonly property bool headerHasCursor: cursorActive && focusSection === "header"
  // Only channels that actually exist get a vote. A box with no default source
  // would otherwise report "input unmuted" forever, leaving the hero switch
  // able to mute but never to unmute.
  readonly property bool hasOutput: !!(volumeSink && volumeSink.audio)
  // True when there is a default input device with an audio channel.
  readonly property bool hasInput: !!(source && source.audio)
  // True when either channel is on and unmuted.
  readonly property bool anyAudible: (hasOutput && !outputMuted) || (hasInput && !inputMuted)
  // The hero switch's tooltip text for its current state.
  readonly property string toggleHint: anyAudible ? "Mute" : "Unmute"

  // Row background tint under the mouse.
  // qmllint disable missing-property
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  // Row background tint for the keyboard-selected row.
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  // qmllint enable missing-property

  // How many rows a section currently has.
  function sectionCount(section) {
    if (section === "output")
      return displayAudioSinks.length
    if (section === "input")
      return displayAudioSources.length
    if (section === "streams")
      return displayAudioStreams.length
    if (section === "nowplaying")
      return 1
    return 0
  }

  // Whether a section should be shown at all.
  function sectionVisible(section) {
    if (section === "output")
      return true
    if (section === "input")
      return displayAudioSources.length > 0 || !!source
    if (section === "streams")
      return displayAudioStreams.length > 0
    if (section === "nowplaying")
      return nowPlaying.visible
    return false
  }

  // Whether a section has its own slider row (output/input do, streams do not).
  function sectionHasSlider(section) {
    if (section === "output")
      return true
    if (section === "input")
      return !!source
    return false
    // stream rows carry their own sliders inline; not a section-level slider
  }

  // Order of visible sections, recomputed reactively so dropping a section
  // (e.g. no input devices) doesn't leave the cursor pointing at it.
  readonly property var visibleSections: {
    var list = []
    if (sectionVisible("output"))
      list.push("output")
    if (sectionVisible("input"))
      list.push("input")
    if (sectionVisible("streams"))
      list.push("streams")
    if (sectionVisible("nowplaying"))
      list.push("nowplaying")
    return list
  }

  // Moves the keyboard cursor up/down within and across sections.
  function moveCursor(delta) {
    var sections = visibleSections
    if (sections.length === 0)
      return
    if (focusSection === "header") {
      if (delta > 0) {
        focusSection = sections[0]
        selectedIndex = sectionHasSlider(sections[0]) ? -1 : 0
      }
      return
    }
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = sectionHasSlider(focusSection) ? -1 : 0
      return
    }

    var idx = selectedIndex
    var max = sectionCount(focusSection) - 1
    // last device index
    var hasSlider = sectionHasSlider(focusSection)
    var floor = hasSlider ? -1 : 0
    // -1 = slider row

    if (delta > 0) {
      if (idx < max) {
        selectedIndex = idx + 1
        return
      }
      // Fall through to next section.
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionHasSlider(focusSection) ? -1 : 0
      }
    } else {
      if (idx > floor) {
        selectedIndex = idx - 1
        return
      }
      // Escape upward.
      if (sIdx > 0) {
        focusSection = sections[sIdx - 1]
        var prevMax = sectionCount(focusSection) - 1
        selectedIndex = prevMax >= 0 ? prevMax : (sectionHasSlider(focusSection) ? -1 : 0)
      } else {
        focusSection = "header"
      }
    }
  }

  // Puts the keyboard cursor on the hero mute switch.
  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    selectedIndex = -1
  }

  // Tab/Shift+Tab: jumps the cursor to the next or previous section.
  function moveSection(delta) {
    var sections = visibleSections
    if (sections.length === 0)
      return
    var current = sections.indexOf(focusSection)
    if (current < 0)
      current = delta > 0 ? -1 : 0
    var next = (current + delta + sections.length) % sections.length
    focusSection = sections[next]
    selectedIndex = sectionHasSlider(focusSection) ? -1 : 0
    cursorActive = true
  }

  // Adjust the slider associated with the focused section. Output and
  // input sliders are real volume controls; on stream rows h/l adjusts
  // that stream's volume (so keyboard parity with the inline slider).
  // For device rows (selectedIndex >= 0 in output/input) h/l is a no-op
  // — the cursor is on a discrete row, not on the slider, and silently
  // moving the global slider would surprise the user.
  function adjustVolume(delta) {
    if (focusSection === "output" && selectedIndex === -1) {
      setOutputVolume(outputVolume + delta)
      return
    }
    if (focusSection === "input" && selectedIndex === -1) {
      setInputVolume(inputVolume + delta)
      return
    }
    if (focusSection === "streams" && selectedIndex >= 0 && selectedIndex < displayAudioStreams.length) {
      var s = displayAudioStreams[selectedIndex]
      if (s && s.audio)
        s.audio.volume = Math.max(0, Math.min(1.5, s.audio.volume + delta))
      return
    }
    if (focusSection === "nowplaying" && transportPlayer) {
      if (delta < 0 && transportPlayer.canGoPrevious)
        transportPlayer.previous()
      else if (delta > 0 && transportPlayer.canGoNext)
        transportPlayer.next()
    }
  }

  // Enter/Space: activate whatever the cursor is on.
  function activateCursor() {
    if (focusSection === "header") {
      toggleAllMuted()
      return
    }
    if (focusSection === "output") {
      if (selectedIndex === -1) {
        toggleOutputMute()
        return
      }
      var sink = displayAudioSinks[selectedIndex]
      if (sink)
        requestDefault("output", sink)
      return
    }
    if (focusSection === "input") {
      if (selectedIndex === -1) {
        toggleInputMute()
        return
      }
      var src = displayAudioSources[selectedIndex]
      if (src)
        requestDefault("input", src)
      return
    }
    if (focusSection === "streams" && selectedIndex >= 0) {
      var st = displayAudioStreams[selectedIndex]
      if (st && st.audio)
        st.audio.muted = !st.audio.muted
      return
    }
    if (focusSection === "nowplaying" && transportPlayer && transportPlayer.canTogglePlaying)
      transportPlayer.togglePlaying()
  }

  onOpenedChanged: {
    syncDefaultOwner()
    // Stand-ins never carry over into an open or past a close.
    audioShowcase = null
    if (opened) {
      refreshDisplayAudioModels()
      focusSection = "output"
      selectedIndex = -1
      // first keyboard cursor reveal starts on the output slider
      cursorActive = false
      keyboardCursor = false
      Qt.callLater(resetScroll)
    } else {
      // A queued default never runs with nobody watching; one in flight
      // finishes (or times out).
      clearDisplayAudioModels()
      outputSignal = 0
      inputSignal = 0
    }
  }

  // Clamp / repair the cursor whenever any list refreshes underneath us.
  onAudioSinksChanged: scheduleDisplayAudioModelRefresh()
  onAudioSourcesChanged: scheduleDisplayAudioModelRefresh()
  onAudioStreamsChanged: scheduleDisplayAudioModelRefresh()
  onUnpluggedSinksChanged: scheduleDisplayAudioModelRefresh()

  // Copies a live Pipewire list into a plain array snapshot.
  function listSnapshot(list) {
    return Model.listSnapshot(list)
  }

  // Rebuilds the display snapshots from the live audio lists and re-clamps the cursor.
  function refreshDisplayAudioModels() {
    if (!opened)
      return
    displayAudioSinks = listSnapshot(audioSinks)
    displayAudioSources = listSnapshot(audioSources)
    displayAudioStreams = listSnapshot(audioStreams)
    displayUnpluggedSinks = listSnapshot(unpluggedSinks)
    clampCursor()
  }

  // Debounces a display-model refresh while the panel is open.
  function scheduleDisplayAudioModelRefresh() {
    if (!opened)
      return
    audioModelRefreshTimer.restart()
  }

  // Detaches the display snapshots when the panel closes.
  function clearDisplayAudioModels() {
    audioModelRefreshTimer.stop()
    displayAudioSinks = []
    displayAudioSources = []
    displayAudioStreams = []
    displayUnpluggedSinks = []
  }

  // Keep the keyboard-focused row inside the visible part of the dropdown's
  // Flickable. The view's rows carry objectNames (channelSlider, deviceRow,
  // streamRow, nowPlaying) and their Repeater index, so the cursor's
  // section and index find the row without the view knowing about scrolling.
  function resetScroll() {
    scrollArea.contentY = 0
  }

  // The section item of the dropdown for a cursor section, or null.
  function cursorSectionItem(section) {
    var names = {
      "output": "outputSection",
      "input": "inputSection",
      "streams": "sourcesSection",
      "nowplaying": "nowPlaying"
    }
    var kids = dropdown.children
    for (var i = 0; i < kids.length; i++)
      if (kids[i].objectName === names[section])
        return kids[i]
    return null
  }

  // The first descendant of ITEM named NAME (with Repeater index INDEX, if given).
  function findNamed(item, name, index) {
    var kids = item ? item.children : []
    for (var i = 0; i < kids.length; i++) {
      var kid = kids[i]
      if (kid.objectName === name && (index === undefined || kid.index === index))
        return kid
      var found = findNamed(kid, name, index)
      if (found)
        return found
    }
    return null
  }

  // Scrolls the keyboard-focused row into view.
  function ensureCursorVisible() {
    if (!cursorActive || !keyboardCursor)
      return
    var maxY = Math.max(0, scrollArea.contentHeight - scrollArea.height)
    if (maxY <= Style.space(24) || focusSection === "header" || (focusSection === "output" && selectedIndex === -1)) {
      scrollArea.contentY = 0
      return
    }
    var section = cursorSectionItem(focusSection)
    if (!section)
      return
    var item = section
    if (focusSection === "streams")
      item = findNamed(section, "streamRow", selectedIndex) || section
    else if (focusSection !== "nowplaying")
      item = selectedIndex === -1 ? (findNamed(section, "channelSlider") || section) : (findNamed(section, "deviceRow", selectedIndex) || section)
    var margin = 6
    var top = item.mapToItem(dropdown, 0, 0).y
    var bottom = top + item.height
    if (top < scrollArea.contentY + margin)
      scrollArea.contentY = Math.max(0, Math.min(maxY, top - margin))
    else if (bottom > scrollArea.contentY + scrollArea.height - margin)
      scrollArea.contentY = Math.max(0, Math.min(maxY, bottom + margin - scrollArea.height))
  }

  onFocusSectionChanged: Qt.callLater(ensureCursorVisible)
  onSelectedIndexChanged: Qt.callLater(ensureCursorVisible)
  onCursorActiveChanged: Qt.callLater(ensureCursorVisible)
  onKeyboardCursorChanged: Qt.callLater(ensureCursorVisible)

  // Keeps focusSection/selectedIndex valid after a list changes underneath them.
  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length)
      return
    // "header" is virtual and never appears in visibleSections, so it has to
    // be let through: muting republishes the PipeWire snapshot, and clamping
    // would knock the cursor off the hero switch on every toggle.
    if (focusSection === "header")
      return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = visibleSections[0]
      selectedIndex = sectionHasSlider(focusSection) ? -1 : 0
      return
    }
    var count = sectionCount(focusSection)
    var hasSlider = sectionHasSlider(focusSection)
    var floor = hasSlider ? -1 : 0
    if (selectedIndex > count - 1)
      selectedIndex = Math.max(floor, count - 1)
    if (selectedIndex < floor)
      selectedIndex = floor
  }

  // The bar/hero speaker glyph for a given (or the current) output volume.
  function outputIcon(volume) {
    // Match the old Waybar pulseaudio glyph set. The Material Design speaker
    // icons render visually smaller in JetBrainsMono Nerd Font.
    if (!sink || !sink.audio)
      return String.fromCodePoint(0xEEE8)
    if (isHeadphones(sink))
      return String.fromCodePoint(0xF02CB)
    if (outputMuted)
      return String.fromCodePoint(0xEEE8)
    var v = volume === undefined ? outputVolume : volume
    if (v >= 0.67)
      return String.fromCodePoint(0xF028)
    if (v >= 0.34)
      return String.fromCodePoint(0xF027)
    if (v > 0)
      return String.fromCodePoint(0xF026)
    return String.fromCodePoint(0xEEE8)
  }

  // The microphone glyph for the current input mute state.
  function inputIcon() {
    if (!source || !source.audio)
      return String.fromCodePoint(0xF036D)
    return inputMuted ? String.fromCodePoint(0xF036D) : String.fromCodePoint(0xF036C)
  }

  // Playful mood-name for a given output volume. Mirrors the brightness
  // panel's brightnessName ladder; bands are wide enough that small
  // tweaks don't rename the room you're in.
  function outputVolumeName(volume, muted) {
    return Model.outputVolumeName(volume, muted)
  }

  // Clamps and applies a new output volume, returning the applied value.
  function setOutputVolume(v) {
    if (!volumeSink || !volumeSink.audio)
      return outputVolume
    var volume = Math.max(0, Math.min(1, v))
    volumeSink.audio.volume = volume
    return volume
  }

  // Summons the on-screen volume display.
  function showVolumeOsd(volume) {
    // qmllint disable missing-property
    if (!bar || !bar.shell)
      return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: outputIcon(volume),
      value: Math.round(volume * 100)
    }))
    // qmllint enable missing-property
  }

  // Clamps and applies a new input volume.
  function setInputVolume(v) {
    if (!source || !source.audio)
      return
    source.audio.volume = Math.max(0, Math.min(1, v))
  }

  // Flips the resolved output sink's mute state.
  function toggleOutputMute() {
    if (volumeSink && volumeSink.audio)
      volumeSink.audio.muted = !volumeSink.audio.muted
  }

  // Flips the default input device's mute state.
  function toggleInputMute() {
    if (source && source.audio)
      source.audio.muted = !source.audio.muted
  }

  // The hero switch is the whole panel's on/off, so it carries both channels
  // at once. It reads as on while anything is still audible, which keeps
  // muting a single channel from the row below flipping the master switch.
  function toggleAllMuted() {
    var mute = anyAudible
    if (hasOutput)
      volumeSink.audio.muted = mute
    if (hasInput)
      source.audio.muted = mute
  }

  // Route default picks to one owner without duplicating its queue or timers.
  function requestDefault(channel, node) {
    syncDefaultOwner()
    if (defaultOwner && !audioShowcase)
      defaultOwner.requestDefault(channel, node)
  }

  // Delegates to Model.js's device label cleanup.
  function friendlyDeviceLabel(text) {
    return Model.friendlyDeviceLabel(text)
  }

  // Delegates to Model.js's device label for a node.
  function nodeLabel(node) {
    return Model.nodeLabel(node)
  }

  // Delegates to Model.js's safe property-bag accessor.
  function nodeProps(node) {
    return Model.nodeProps(node)
  }

  // Delegates to Model.js's headphone/headset detection.
  function isHeadphones(node) {
    return Model.isHeadphones(node)
  }

  // Delegates to Model.js's output-device glyph.
  function sinkGlyph(node) {
    return Model.sinkGlyph(node)
  }

  // Delegates to Model.js's input-device glyph.
  function sourceGlyph(node) {
    return Model.sourceGlyph(node)
  }

  // Delegates to Model.js's stream label cleanup.
  function friendlyStreamLabel(label) {
    return Model.friendlyStreamLabel(label)
  }

  // Delegates to Model.js's normalized stream label key.
  function streamLabelKey(label) {
    return Model.streamLabelKey(label)
  }

  // Delegates to Model.js's generic-label check.
  function streamLabelIsGeneric(label) {
    return Model.streamLabelIsGeneric(label)
  }

  // Delegates to Model.js's raw stream label lookup.
  function rawStreamLabel(node) {
    return Model.rawStreamLabel(node)
  }

  // Delegates to Model.js's MPRIS player label.
  function mprisPlayerLabel(player) {
    return Model.mprisPlayerLabel(player)
  }

  // Delegates to Model.js's playerctld-proxy check.
  function mprisPlayerIsProxy(player) {
    return Model.mprisPlayerIsProxy(player)
  }

  // Delegates to Model.js's stream/player label match.
  function streamRepresentsMprisPlayer(streamLabel, playerLabel) {
    return Model.streamRepresentsMprisPlayer(streamLabel, playerLabel)
  }

  // Delegates to Model.js's MPRIS candidate-label search, bound to mprisPlayers.
  function mprisLabelsFor(predicate) {
    return Model.mprisLabelsFor(mprisPlayers, predicate)
  }

  // Delegates to Model.js's stream-to-player label match, bound to mprisPlayers.
  function matchingMprisStreamLabel(label) {
    return Model.matchingMprisStreamLabel(label, mprisPlayers)
  }

  // Delegates to Model.js's MPRIS candidate search for a generic stream label.
  function unmatchedMprisStreamLabel(label) {
    // Spotify exposes its PipeWire stream as "audio-src". For generic stream
    // names, use the one MPRIS player not already represented by another audio
    // stream (e.g. Chromium, or ALSA apps like cliamp).
    return Model.unmatchedMprisStreamLabel(label, mprisPlayers, displayAudioStreams)
  }

  // Delegates to Model.js's stream display label, bound to mprisPlayers and displayAudioStreams.
  function streamLabel(node) {
    return Model.streamLabel(node, mprisPlayers, displayAudioStreams)
  }

  // Delegates to Model.js's stream/player match, bound to mprisPlayers and displayAudioStreams.
  function streamRepresentsPlayer(node, player) {
    return Model.streamRepresentsPlayer(node, player, mprisPlayers, displayAudioStreams)
  }

  // Plain device rows for the view, from Pipewire NODES (outputs when
  // IS_SINK), keyed by AudioLogic.deviceKey. Which row is the default (and
  // pulses) comes apart, in the view's outputDefault/inputDefault, so a
  // pending switch never rebuilds the rows.
  function deviceRows(nodes, isSink, unplugged) {
    var rows = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      rows.push({
        key: AudioLogic.deviceKey(n),
        label: nodeLabel(n),
        glyph: isSink ? sinkGlyph(n) : sourceGlyph(n),
        detail: AudioLogic.deviceDetail(nodeProps(n), isSink, isHeadphones(n)),
        available: true
      })
    }
    for (var j = 0; j < (unplugged || []).length; j++) {
      var u = unplugged[j]
      rows.push({
        key: AudioLogic.deviceKey(u),
        label: nodeLabel(u),
        glyph: isSink ? sinkGlyph(u) : sourceGlyph(u),
        detail: "unplugged",
        available: false
      })
    }
    return rows
  }
  // The view's output rows. Kept apart from audioView so the arrays keep
  // their identity while the levels tick ~30 times a second. While
  // showcasing, the stand-in labels replace the real ones by position.
  readonly property var outputDeviceRows: Showcase.showcaseLabels(deviceRows(displayAudioSinks, true, displayUnpluggedSinks), audioShowcase ? audioShowcase.outputs : [], "Output")
  // The view's input rows (see outputDeviceRows).
  readonly property var inputDeviceRows: Showcase.showcaseLabels(deviceRows(displayAudioSources, false, []), audioShowcase ? audioShowcase.inputs : [], "Input")
  // The view's stream rows (see outputDeviceRows).
  readonly property var streamRows: Showcase.showcaseLabels(displayAudioStreams.map(function (s) {
    return {
      key: String(s.id),
      label: streamLabel(s),
      volume: s.audio ? s.audio.volume : 0,
      muted: s.audio ? s.audio.muted : false,
      current: streamRepresentsPlayer(s, activeMediaPlayer)
    }
  }), audioShowcase ? audioShowcase.apps : [], "App")
  // Everything the Aranea view draws (AudioDropdown.view).
  readonly property var audioView: ({
      glyph: outputIcon(),
      mood: outputVolumeName(outputVolume, outputMuted),
      anyAudible: anyAudible,
      toggleHint: toggleHint,
      headerCursor: headerHasCursor && keyboardCursor,
      cursor: {
        active: cursorActive && keyboardCursor,
        section: focusSection,
        index: selectedIndex
      },
      output: {
        present: hasOutput,
        volume: outputVolume,
        muted: outputMuted,
        level: outputSignal
      },
      outputDevices: outputDeviceRows,
      outputDefault: outputShown,
      inputVisible: displayAudioSources.length > 0 || !!source,
      input: {
        present: hasInput,
        volume: inputVolume,
        muted: inputMuted,
        level: inputSignal
      },
      inputDevices: inputDeviceRows,
      inputDefault: inputShown,
      streams: streamRows,
      nowPlaying: nowPlaying
    })
  // Carries out one AudioDropdown action. Every action comes from the
  // pointer, so each one hands the cursor back from the keyboard. Device
  // and stream actions are keyed ({index, key}): one whose row no longer
  // holds that node is refused (AudioLogic.nodeAt). A hover is only the
  // rows' own fill: it never moves the cursor or hides the outline.
  function handleAction(name, arg) {
    if (name === "hover")
      return
    keyboardCursor = false
    if (name === "toggleAll")
      toggleAllMuted()
    else if (name === "outputVolume")
      setOutputVolume(arg)
    else if (name === "outputMute")
      toggleOutputMute()
    else if (name === "outputDevice")
      requestDefault("output", AudioLogic.nodeAt(displayAudioSinks, arg.index, arg.key, true))
    else if (name === "inputVolume")
      setInputVolume(arg)
    else if (name === "inputMute")
      toggleInputMute()
    else if (name === "inputDevice")
      requestDefault("input", AudioLogic.nodeAt(displayAudioSources, arg.index, arg.key, true))
    else if (name === "streamVolume") {
      var s = AudioLogic.nodeAt(displayAudioStreams, arg.index, arg.key)
      if (s && s.audio)
        s.audio.volume = Math.max(0, Math.min(1.5, arg.value))
    } else if (name === "streamMute") {
      var m = AudioLogic.nodeAt(displayAudioStreams, arg.index, arg.key)
      if (m && m.audio)
        m.audio.muted = !m.audio.muted
    } else if (name === "previous" && transportPlayer && transportPlayer.canGoPrevious)
      transportPlayer.previous()
    else if (name === "playPause" && transportPlayer && transportPlayer.canTogglePlaying)
      transportPlayer.togglePlaying()
    else if (name === "next" && transportPlayer && transportPlayer.canGoNext)
      transportPlayer.next()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  PwObjectTracker {
    objects: root.audioStreams
  }

  PwNodePeakMonitor {
    id: inputPeakMonitor
    node: root.source
    enabled: root.opened && !!root.source
  }

  PwNodePeakMonitor {
    id: outputPeakMonitor
    node: root.volumeSink
    enabled: root.opened && !!root.volumeSink
  }

  // Samples both peak monitors into the smoothed filament glow. With motion
  // off it samples at 250 ms, so the glow shows the level without pulsing.
  Timer {
    interval: Aranea.DesignTokens.motionEnabled ? 33 : 250
    repeat: true
    running: root.opened
    onTriggered: {
      root.outputSignal = AudioLogic.signalLevel(root.outputSignal, root.outputMuted ? 0 : outputPeakMonitor.peak, interval)
      root.inputSignal = AudioLogic.signalLevel(root.inputSignal, root.inputMuted ? 0 : inputPeakMonitor.peak, interval)
    }
  }

  // Quickshell doesn't update MPRIS position on its own; nudge it each second.
  Timer {
    interval: 1000
    repeat: true
    running: root.opened && !!root.nowPlayingPlayer && root.nowPlaying.playing
    onTriggered: root.nowPlayingPlayer.positionChanged()
  }

  Process {
    id: volumeSinkProc
    command: ["omarchy-audio-output-sink"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.volumeSinkName = String(text).trim()
    }
  }

  // Runs whether or not the panel is open: the bar shows and scrolls the output
  // volume too, so an unresolved sink there would read and change the virtual
  // tuning sink instead of the speakers.
  Timer {
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.resolveVolumeSink()
  }

  Timer {
    id: audioModelRefreshTimer
    interval: 75
    repeat: false
    onTriggered: root.refreshDisplayAudioModels()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.outputIcon()
    onPressed: function (b) {
      root.keyboardCursor = false
      if (b === Qt.RightButton)
        root.toggleAllMuted()
      else
        root.toggle()
    }

    onWheelMoved: function (delta) {
      root.keyboardCursor = false
      if (!root.hasOutput)
        return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0)
        return
      var volume = root.setOutputVolume(root.outputVolume + wheel.steps * 0.05)
      root.showVolumeOsd(volume)
    }
  }

  Aranea.KeyboardPanelFrame {
    id: panel
    refined: true
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(dropdown.implicitHeight, Style.space(560))
    onCloseRequested: root.close()
    onTabRequested: function (direction) {
      dropdown.disarmPointer()
      root.switchPanel(direction)
    }
    onMoveRequested: function (dx, dy) {
      dropdown.disarmPointer()
      // The first key after opening or after mouse use only reveals the
      // cursor where it is.
      if (!root.cursorActive || !root.keyboardCursor) {
        root.cursorActive = true
        root.keyboardCursor = true
        return
      }
      if (dy !== 0)
        root.moveCursor(dy)
      else if (dx !== 0)
        root.adjustVolume(dx * 0.05)
    }
    // Enter, like any first key, only reveals a hidden cursor; it acts only
    // on the outlined row.
    onActivateRequested: {
      dropdown.disarmPointer()
      if (!root.cursorActive || !root.keyboardCursor) {
        root.cursorActive = true
        root.keyboardCursor = true
        return
      }
      root.activateCursor()
    }
    onTextKey: function (t) {
      dropdown.disarmPointer()
      // 'm' mutes whatever the cursor is on: focused section's slider
      // for output/input, the focused stream for streams.
      if (t === "m" || t === "M") {
        if (!root.cursorActive)
          return
        root.keyboardCursor = true
        if (root.focusSection === "streams" && root.selectedIndex >= 0 && root.selectedIndex < root.displayAudioStreams.length) {
          var s = root.displayAudioStreams[root.selectedIndex]
          if (s && s.audio)
            s.audio.muted = !s.audio.muted
        } else if (root.focusSection === "input") {
          root.toggleInputMute()
        } else if (root.focusSection === "nowplaying") {
          return
        } else {
          root.toggleOutputMute()
        }
      }
    }

    Flickable {
      id: scrollArea
      anchors.fill: parent
      contentHeight: dropdown.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      // Only scroll when the dropdown overflows, as stock's ScrollView did,
      // so drags on the sliders are never taken for a flick.
      interactive: contentHeight > height
      onContentHeightChanged: returnToBounds()

      AudioDropdown {
        id: dropdown
        width: scrollArea.width
        view: root.audioView
        onAction: function (name, arg) {
          root.handleAction(name, arg)
        }
      }
    }
  }
}
