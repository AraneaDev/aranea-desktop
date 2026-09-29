# Aranea updates

`araneadev.updates` provides the update service and its bar widget. The
manifest exposes `Service.qml` and `BarWidget.qml`.

## Responsibilities

- Read update availability and group results by source.
- Represent reboot-required and stale refresh states.
- Show compact status in the bar and detailed update information in the panel.
- Delegate installation to the host updater instead of installing packages in
  the bar.

`Service.qml` owns polling and service publication. `BarWidget.qml` is the bar
entry point. `UpdatePanelHost.qml` owns panel hosting and `UpdatePanel.qml`
owns the presentational update list.

## Logic boundaries

- `UpdateLogic.js` owns parsing, normalization, and severity mapping.
- `araneadev.shared/StatusRow.qml` owns the reusable status-row contract.
- QML owns composition and the host updater action.

## Validation

Run `tests/qml-behaviour.test.sh updates-widget` and the update JS suite.
