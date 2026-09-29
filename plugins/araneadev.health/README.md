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

## Logic boundaries

- `HealthLogic.js` owns health normalization and problem policy.
- `HealthPresentation.js` owns display formatting.
- `MetricsLogic.js` owns metric parsing and rate calculations.
- `HealthBridge.js` publishes the current service through shared registry
  infrastructure.

## Validation

Use `tests/qml-behaviour.test.sh health health-panel-components` and the health
and metrics JS suites.
