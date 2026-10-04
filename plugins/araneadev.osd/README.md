# Aranea OSD

`araneadev.osd` is the compact on-screen display panel. Its manifest exposes
`Osd.qml` as a panel entry point and keeps the panel loaded for fast feedback.

## Responsibilities

- Display brightness, volume, microphone, and other transient levels.
- Render the Aranea filament gauge and semantic state colors.
- Normalize values and clamp unsafe input before presenting them.

`Osd.qml` owns the panel and visual composition; `OsdStrand.qml` draws the
level strand (the mint-to-violet Filament gradient and the accent knob).
`OsdModel.js` owns pure value
normalization and display policy. It uses shared tokens but does not own bar or
notification lifecycle.

## Validation

Run `tests/qml-behaviour.test.sh osd-strand overlay-components` and the OSD JS
suite.
