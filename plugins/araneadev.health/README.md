# Aranea health

`araneadev.health` provides a service and bar widget for system health. The
manifest exposes `Service.qml` and `Panel.qml`, and keeps the service loaded.

## Responsibilities

- Track failed systemd units, disk pressure, reboot requirements, and Docker
  restart loops.
- Sample CPU, memory, load, network, and process metrics.
- Publish a compact health status to the bar and a detailed dropdown panel.
- Keep health in the dropdown instead of creating notification-center items.

`Service.qml` owns polling and service publication. `Panel.qml` is the bar
entry point. `Monitor.qml` and `Metrics.qml` own the metrics surface, while
the three `Health*Section.qml` components compose problem, process, and
resource groups.

## The dropdown

`Panel.qml` draws the dropdown in the shared `KeyboardPanelFrame`, with a
`DropdownHeader` (the health glyph, the hostname and the uptime) and a key
hint at the bottom.

- **Problems** (`HealthProblemsSection.qml`): one `NodeDeviceRow` per open
  problem, its node tinted urgent (critical) or amber (attention). Rows are
  keyed by the problem's id, falling back to its text
  (`HealthLogic.problemKey`), and a click or Enter whose row no longer
  carries its key is refused (`keyedProblem`). The Repeater runs over the
  row count, so a refresh never recreates a row; a real re-sort stamps the
  layout and clicks settle for 300 ms after it.
- **Keyboard:** up and down walk the problems; Enter or Space opens one
  (its `execArgv`), Esc closes, Tab switches dropdowns. The mint outline
  shows only while the keyboard drives the cursor, and the first key after
  opening or after pointer use (Enter included) only reveals it, on the
  first problem after opening (`cursorMove`, `cursorPress`,
  `outlineIndex`, which wrap the shared keyed cursor in
  `araneadev.shared/CursorLogic.js`). Pointer hover only draws the row's
  hover fill, after a real move; it never moves the cursor or the outline.
- **Resources** (`HealthResourceSection.qml`): the CPU trace is the shared
  `LinkGraph` over the last 60 one-second samples (`cpuSamples`); memory and
  disk use are `FilamentBar` strand bars (`barFraction`), their values
  tinted by usage level. NET and TOP keep their content, with the same
  caption labels.
- **Usage level colour:** the amber or urgent level now shows on the value
  text, because the bars are always the mint to violet strand.

## Logic boundaries

- `HealthLogic.js` owns health normalization and problem policy.
- `HealthPresentation.js` owns display formatting.
- `MetricsLogic.js` owns metric parsing and rate calculations.
- `HealthBridge.js` publishes the current service through shared registry
  infrastructure.

## Validation

Use `tests/qml-behaviour.test.sh health health-panel-components health-keyed`
and the health and metrics JS suites.
