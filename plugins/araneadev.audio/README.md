# Aranea audio

`araneadev.audio` replaces Omarchy's `omarchy.audio` bar dropdown. It keeps
stock's logic (Pipewire devices and streams, the keyboard cursor, the bar
icon's scroll and right-click) and draws an Aranea view: Filament sliders
with a live signal glow, web-node device rows, per-app sources and a Now
playing strip.

## Validation

Run `node --test tests/js/audio-logic.test.js` and
`tests/qml-behaviour.test.sh audio-dropdown filament-components`.
