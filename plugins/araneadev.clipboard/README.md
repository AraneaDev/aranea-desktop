# Aranea clipboard

`araneadev.clipboard` is a persistent overlay for clipboard history. The
manifest exposes `Clipboard.qml` as an overlay and keeps the plugin loaded so
history remains available between openings.

## Responsibilities

- Capture and persist clipboard history through the Omarchy clipboard bridge.
- Normalize legacy and typed entries.
- Detect links, paths, colors, code, images, and secret-like content.
- Support search, pinning, masking, expiry, preview, copy, and insertion.

`Clipboard.qml` owns service state and overlay lifecycle. `ClipboardWindow.qml`
is the visual window. The components under `components/` own result rows and
preview composition.

## Logic boundaries

- `ClipboardLogic.js` owns history policy and secret handling.
- `ClipboardNormalization.js` owns entry shape compatibility.
- `ClipboardPresentation.js` owns display formatting.
- QML owns composition, selection, and user interaction.

Shared chrome comes from `araneadev.shared`. Do not duplicate token values or
rebuild runtime paths in this plugin.

## Validation

Coverage includes `tests/qml/clipboard.qml`,
`tests/qml/clipboard-components.qml`, and
`tests/qml/clipboard-preview-components.qml`, plus the clipboard JS suites.
