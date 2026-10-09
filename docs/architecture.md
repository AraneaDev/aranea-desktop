# Architecture

Aranea is a theme, shell extension, integration bundle, and set of safe
installation tools. The repository keeps those concerns separate so visual
changes can be made centrally without coupling runtime behavior to generated
assets or host state.

## System shape

```mermaid
flowchart TD
    Tokens[design/tokens.toml] --> Generator[scripts/generate-tokens]
    Templates[design/templates] --> Generator
    Generator --> Projections[Committed projections]
    Projections --> GTK[GTK and desktop styling]
    Projections --> QMLTokens[QML token module]
    Projections --> Shell[Shell and terminal config]
    Projections --> Assets[GTK, cursor, and SVG assets]
    Shared[araneadev.shared] --> Bar[Bar]
    Shared --> Menu[Menu]
    Shared --> Panels[Panels and pickers]
    Shared --> Lock[Lock and polkit]
    Shared --> Updates[Updates and workspaces]
    Logic[Focused JS logic modules] --> Facades[Generated QML JS facades]
    Facades --> Bar
    Facades --> Menu
    Facades --> Panels
    Hooks[Theme hooks] --> Runtime[Omarchy and Quickshell runtime]
    Projections --> Runtime
    Bar --> Runtime
    Menu --> Runtime
    Panels --> Runtime
    Lock --> Runtime
```

The arrows describe ownership and data flow, not import syntax. The important
boundaries are:

| Layer                | Owns                                                        | Must not own                                               |
| -------------------- | ----------------------------------------------------------- | ---------------------------------------------------------- |
| Tokens and templates | Palette, spacing, typography, motion, and asset projections | Plugin state or host detection                             |
| Shared QML           | Reusable visual and input contracts                         | Plugin lifecycle, IPC, cursor state, or process management |
| Plugin entry points  | Composition, lifecycle, and plugin-specific interaction     | Duplicated global chrome or token literals                 |
| Focused JS modules   | Pure domain logic and normalization                         | QML window lifecycle or generated facade structure         |
| Generated facades    | Stable compatibility exports for QML                        | Hand-edited business logic                                 |
| Hooks and scripts    | Installation, activation, repair, and host integration      | Presentation decisions that belong in QML or templates     |

Desktop search normalization and ranking live in `DesktopSearchRanking.js`.
The generated `DesktopSearchLogic.js` facade composes it with `MenuSearch.js`,
so matching shares the menu’s existing name, alias, and whole-word description
semantics. The menu host owns source refresh and activation; canonical result
keys and typed targets let it re-resolve a selection against current state.

`DesktopSearchSources.qml` consumes the menu host's existing `appRows`, merged
`menuItems`/`itemOrder`, guard results and app history. It uses `MenuModel.isVisible`
for command destinations and the existing settings manifest availability. Its
`setActive(bool)` boundary gates compositor subscriptions and snapshot iteration;
a 100 ms timer coalesces changes, and generation checks discard old completions.
`records`, `available` (live compositor availability) and `revision` expose source
state; query ranking and selected-key ownership remain in the menu host.

`DesktopSearchTargets.js` adapts those raw snapshots into typed records and
returns host requests or argument arrays. On `activate(key)`, the controller
reads a fresh synchronous snapshot and re-resolves the key through
`DesktopSearchLogic.resolveTarget`, independently of cached refresh records.
`appRequested(appId, label)` and `commandRequested(itemId)` preserve the existing
launch and menu handlers. Settings results summon one of four static sections;
window/workspace targets use validated exact identities in the installed Lua
focus dispatcher. Titles, descriptions and queries stay display data. Missing
compositor data affects only live results. Failed or vanished activation emits
`failed(message)` without closing; `activated()` reports an accepted argument-array
submission. Apps and commands leave closing/navigation to their existing handlers.

`Menu.qml` owns root-only ranking and selected-key reconciliation. Query changes
select the highest-ranked row; refreshes retain its canonical identity or clear
selection if it disappears. The optional desktop roles are cleared when returning
to scoped/dmenu rows, including reused ListModel delegates. `MenuSurface.qml` shares
the production card with `MenuWindow.qml` and the inert offscreen renderer; window
placement, pointer gate, lifecycle and cursor state stay in the existing hosts.

Tests can replace the compositor, raw window/workspace fixtures, synchronous
`snapshotReader()`, asynchronous `refreshReader(generation, complete)` and
`runner(argv)` boundaries. Refresh completion must echo its generation; it never
becomes the activation snapshot. The production runner uses
`Quickshell.execDetached` with argument arrays, so accepted dispatch does not
claim the external command completed successfully.

`DesktopActionRecords.js` projects DND, audio and wallpaper snapshots into typed
Action records; `DesktopActionState.js` tracks one request per family with
generation IDs and keyed feedback. `DesktopActionController.qml` lives outside
the menu window. It observes notification preference echoes and the audio
plugin’s keep-loaded `AudioDefaults.qml` service, which also owns the panel’s
default-device queue. Search never duplicates device state.

`DesktopWallpaperActions.qml` owns tracked processes, fresh manifest validation
and active-ID readback. Confirmation deadlines are three seconds for DND, four
for audio and fifteen for wallpaper. Menu closure releases observation leases
without cancelling submitted work. Activation resolves current exact identities;
feedback is excluded from matching. Accepted actions retain the menu, unlike
normal argument-array launch requests. Inert showcase snapshots refuse dispatch
and cannot replace outstanding requests.

## Token flow

`design/tokens.toml` is the source of truth. Templates describe the target
format, and the generator renders committed files for each consumer. A change
to a color, dimension, or motion value should start in the token source or its
template, not in a generated CSS, TOML, QML, SVG, or cursor file.

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Source as tokens.toml
    participant Gen as token generator
    participant Files as committed projections
    participant Check as tools/check
    Dev->>Source: Edit canonical token
    Dev->>Gen: scripts/generate-tokens --write
    Gen->>Files: Render all projections
    Dev->>Check: scripts/generate-tokens --check
    Check-->>Dev: Pass or report drift
```

Generated files are useful review artifacts and runtime inputs, but they are
not an editing boundary. The same rule applies to JS facades generated by
`tools/js-facade-generator.mjs`.

## Runtime composition

Plugin entry points should remain composition roots. Shared components remove
repeated contracts while leaving ownership with the plugin that understands
the behavior.

```mermaid
flowchart LR
    Entry[Plugin entry point] --> State[Plugin state and lifecycle]
    Entry --> SharedChrome[Shared chrome]
    Entry --> Feature[Feature component]
    State --> Feature
    SharedChrome --> Tokens[Aranea tokens]
    Feature --> Logic[Focused logic module]
    Logic --> Stable[Stable facade API]
```

Current shared examples include `BrandHeader`, `StatusRow`,
`KeyboardInputFrame`, `KeyboardPanelFrame`, `RuntimePaths`, `SurfaceCard`,
`PanelHeader`, `StatusRail`, and `StatusTextPair`.

Extract a component when the contract is repeated, stable, and presentational.
Keep it local when it depends on plugin state, a particular service, a cursor,
or a one-off interaction. Prefer explicit properties and signals over reaching
through root IDs.

## Logic and facade decomposition

Large QML-compatible JavaScript facades preserve the public function names
used by QML. Focused modules own the implementation and tests.

```mermaid
flowchart TD
    QML[QML caller] --> Facade[Generated facade]
    Facade --> Search[Search module]
    Facade --> Tree[Tree and route module]
    Facade --> Settings[Settings module]
    Facade --> Domain[Other focused domain modules]
    Search --> Tests[Direct module tests]
    Tree --> Tests
    Settings --> Tests
    Domain --> Tests
```

When decomposing logic:

1. Preserve the facade's exported names and QML-compatible syntax.
2. Move one pure domain at a time into a sibling module.
3. Add direct tests for the new module before removing duplicate logic.
4. Regenerate the facade and run `node tools/js-facade-generator.mjs --check`.

## Validation boundaries

```mermaid
flowchart LR
    Edit[Change] --> Format[format and lint]
    Format --> Contracts[shell, JS, QML contracts]
    Contracts --> Runtime[QML behavior and smoke]
    Runtime --> Review[Review generated diffs and docs]
    Review --> Release[Merge and release]
```

Use the narrowest useful check while iterating, then finish with the complete
repository gate:

```bash
scripts/generate-tokens --check
node tools/js-facade-generator.mjs --check
tests/qml-types.test.sh
tests/qml-behaviour.test.sh shared updates-widget workspaces-widget overlay-components polkit-components
tools/check
```

`tools/check --fast` is useful for local iteration. The full command is the
release gate because it includes slow contract tests and runtime smoke checks
when the host provides the required Omarchy and Quickshell dependencies.

## Further reading

- [Development](development.md) for repository conventions and extraction
  boundaries.
- [Agent development guide](agent-development.md) for safe automated changes.
- [Agent interface](agent-interface.md) for the installer and repair JSONL
  protocol.
- [Visual language](visual-language.md) for user-facing design principles.
