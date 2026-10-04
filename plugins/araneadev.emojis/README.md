# Aranea emoji picker

`araneadev.emojis` is the searchable emoji overlay. Its manifest exposes
`Emojis.qml` and keeps the plugin loaded for quick reopening.

## Responsibilities

- Load the checked-in `emojis.json` dataset.
- Normalize queries and search keywords.
- Persist a bounded recent emoji list.
- Insert into the active application or copy when insertion is unavailable.
- Render the picker chrome, result grid, and reusable emoji cells.

`Emojis.qml` owns filtering, recents, persistence, keys, and insertion; it
creates `EmojiWindow.qml` (the overlay window) unless `windowEnabled` is off,
so tests run it offscreen. The presentational split is `EmojiPickerChrome`
and `EmojiPickerContent`, with `EmojiGrid` and `EmojiCell` owning result
rendering and click emission.

## Pointer rules

The mint outline marks the emoji Enter will insert: it shows from open (on
the first recent, or the first cell) and after typing, and never with no
results. Only the keyboard moves it. Hover only fills the cell the pointer
really moved onto (PointerMoveGate). Clicks are keyed by the emoji pressed
and settled: a release on a cell that now holds another emoji, or within
300 ms of the cells changing or scrolling under a still pointer, is refused.

## Logic boundaries

- `EmojiLogic.js` owns dataset parsing, recents, and insertion helpers.
- `EmojiSearch.js` owns normalized matching and result limits.
- QML owns layout and selection reporting.

Use shared tokens and shared overlay primitives instead of local visual copies.

## Validation

Run `tests/qml-behaviour.test.sh emoji-components emoji-pointer` and the emoji JS suites in
`tests/js/`.
