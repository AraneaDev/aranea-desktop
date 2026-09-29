# Aranea polkit

`araneadev.polkit` is the authentication prompt service. Its manifest exposes
`PolkitAgent.qml` and declares the Omarchy authentication capability.

## Responsibilities

- Register the polkit agent and receive authentication requests.
- Parse action, command, identity, prompt, and PAM metadata.
- Present a lock-style prompt with safe markup and identity context.
- Preserve native password and fingerprint authentication behavior.

`PolkitAgent.qml` and `PolkitAgentService.qml` own service registration and
request lifecycle. `PolkitWindow.qml` owns the window. `PolkitPromptCard.qml`
composes the shared `BrandHeader`, details, and authentication field.

## Logic boundaries

- `PolkitLogic.js` owns parsing, validation, escaping, and display projections.
- QML owns the prompt lifecycle and user input.
- `araneadev.shared` owns reusable branded chrome and tokens.

## Validation

Run `tests/qml-behaviour.test.sh polkit-components polkit` and the polkit JS
suites.
