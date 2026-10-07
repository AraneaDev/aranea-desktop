# Aranea audio

`araneadev.audio` replaces Omarchy's `omarchy.audio` bar dropdown. It keeps
stock's logic (Pipewire devices and streams, the keyboard cursor, the bar
icon's scroll and right-click) and draws an Aranea view: Filament sliders
with a live signal glow, web-node device rows, per-app sources and a Now
playing strip whose progress bar is lit as the filament strand.

The keep-loaded `Service.qml` owns default-device selection through
`AudioDefaults.qml`. Panels on multiple monitors and desktop search share that
owner, its exact device identities, and its confirmation state. Closing a panel
does not cancel a search request. Search results use fresh available devices;
the panel's cached display fallback cannot dispatch a removed device.

## Behaviour

- Choosing a device (a click or Enter) shows it as the default at once.
  Its row pulses until PipeWire reports it. Choices made meanwhile queue,
  and the last one wins. After 4 s the rows fall back to the real default.
- Device and stream actions carry the node id. An action whose row now
  holds another node (a re-sort, a stream leaving) is refused. A stream
  slider drag keeps the stream it started on.
- A device or stream joining, leaving or re-sorting, a section showing or
  hiding, and Now playing showing or hiding stamp the layout. A click on a
  row, a slider, the mute switch, a stream's mute glyph or a transport
  button within 300 ms of a stamp is ignored unless the pointer has really
  moved there since.
- **`showcase` IPC:** for README captures, stand-in labels replace the
  output, input and stream rows' names by position (the rows, their kinds
  and the default stay real), and a made-up track with a position fills
  Now playing, even with no player running. Display only: PipeWire and the
  players are never touched, the transport controls are refused while it
  is shown, and it clears when the dropdown opens or closes. Closed, the
  call answers `closed`; a bad payload, `invalid`.

  ```bash
  omarchy-shell omarchy.audio showcase ' {"outputs":["Studio Monitors"],"inputs":["Desk Mic"],"apps":["Spotify"],"track":{"title":"Midnight City","artist":"M83","player":"Spotify","progress":0.4}}'
  ```

## Validation

Run `node --test tests/js/audio-logic.test.js` and
`tests/qml-behaviour.test.sh audio-dropdown audio-keyed filament-components`.
