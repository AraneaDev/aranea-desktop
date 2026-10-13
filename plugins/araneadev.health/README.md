# Aranea health

`araneadev.health` provides a service and bar widget for system health. The
manifest exposes `Service.qml` and `Panel.qml`, and keeps the service loaded.

On the consolidated bar, `alertOnly: true` keeps the Health shortcut hidden until
there is an open issue. Its anchor remains visible while the issue panel is open,
even if the final issue clears. Regular resources remain available in the
Battery/System Health tab; standalone layouts retain the permanent Health icon.

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
pure `HealthDropdown` view: hostname and uptime, a compact availability/healthy caption,
all actionable problems, expanded Resource details and an optional
Processes section, and a fixed muted keyboard hint. The host owns expansion,
lifecycle and keyed cursor state. Unknown metrics display an em dash; an unavailable service
reads “Health data unavailable”. Resources start expanded on every open; Processes
starts collapsed. The wider panel puts memory and disk side by side, with a larger
CPU trace spanning the width. Narrow screens return to one resource column.
Collapsing resources reveals the compact CPU/memory/fullest-disk summary.
Expanded content scrolls within the host's available-height budget.

Issues use one compact heading and keyed row list, with no repeated issue-count
and severity block. Clicking “Resolve” or activating a row closes the dropdown
and opens `scripts/aranea-health-resolve` in a terminal. It shows diagnostics
for that exact issue and offers a guided next step: service/container restart,
disk folder inspection and usage analysis, or a kernel-update reboot. Opening
the tool performs only diagnostics; restart/reboot requires selecting the action
and confirming it. The tool never deletes files. Successful actions request a
fresh health check. Systems without the terminal launcher retain their native
disk and reboot actions.

For an intentionally stopped container, the troubleshooting menu also offers
`a` to acknowledge that stop. `scripts/aranea-health-ack` stores the container ID
and precise Docker finish time in Aranea's user state. The monitor validates
that occurrence before hiding its row, including after a shell restart. A
new stop, a replacement container, or a running container never inherits the
acknowledgment. Other health checks remain visible. `aranea-health-ack forget
container:NAME` reverses an acknowledgment.

- **Problems** (`HealthProblemsSection.qml`): one `NodeDeviceRow` per open
  problem, its node tinted urgent (critical) or amber (attention). Rows are
  keyed by the problem's id, falling back to its text
  (`HealthLogic.problemKey`), and a click or Enter whose row no longer
  carries its key is refused (`keyedProblem`). The Repeater runs over the
  row count, so a refresh never recreates a row; a real re-sort stamps the
  layout and clicks settle for 300 ms after it.
- **Keyboard:** up and down walk problems and disclosure headings; Enter or Space opens a problem or toggles details
  (its `execArgv`), Esc closes, Tab switches dropdowns. The mint outline
  shows only while the keyboard drives the cursor, and the first key after
  opening or after pointer use (Enter included) only reveals it, on the
  first problem after opening (`cursorMove`, `cursorPress`,
  `outlineIndex`, which wrap the shared keyed cursor in
  `araneadev.shared/CursorLogic.js`). Pointer hover only draws the row's
  hover fill, after a real move; it never moves the cursor or the outline.
  Keyed focus stays visible even when problems reorder without changing total height.
- **Resource details** (`HealthResourceSection.qml`): the CPU trace is the shared
  `LinkGraph` over the last 60 one-second samples (`cpuSamples`); memory and
  disk use are `FilamentBar` strand bars (`barFraction`), their values
  tinted by usage level. NET and TOP keep their content, with the same
  caption labels. Processes has its own optional disclosure, including a readable empty state.
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
