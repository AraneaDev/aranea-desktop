# Aranea emoji picker

`araneadev.emojis` is the searchable emoji overlay. Its manifest exposes
`Emojis.qml` and keeps the plugin loaded for quick reopening.

## Responsibilities

- Load the checked-in `emojis.json` dataset.
- Normalize queries and search keywords.
- Persist a bounded recent emoji list.
- Insert into the active application or copy when insertion is unavailable.
- Render the picker chrome, result grid, and reusable emoji cells.

`Emojis.qml` owns filtering, recents, persistence, and insertion. The
presentational split is `EmojiPickerChrome` and `EmojiPickerContent`, with
`EmojiGrid` and `EmojiCell` owning result rendering and click emission.

## Logic boundaries

- `EmojiLogic.js` owns dataset parsing, recents, and insertion helpers.
- `EmojiSearch.js` owns normalized matching and result limits.
- QML owns layout and selection reporting.

Use shared tokens and shared overlay primitives instead of local visual copies.

## Validation

Run `tests/qml-behaviour.test.sh emoji-components` and the emoji JS suites in
`tests/js/`.
