# Aranea updates

`araneadev.updates` provides the update service and its bar widget. The
manifest exposes `Service.qml` and `BarWidget.qml`.

## Responsibilities

- Read update availability and group results by source.
- Represent reboot-required and stale refresh states.
- Show compact status in the bar and detailed update information in the panel.
- Delegate installation to the host updater instead of installing packages in
  the bar.

`scripts/aranea-update-status` collects repository updates with
`checkupdates --nocolor` and AUR updates with `yay -Qua --color never`, when
yay is available. It uses a private temporary database and never installs
packages. The repository count includes Omarchy itself; an active Omarchy
development checkout also retains its native availability check. AUR results
honor the native updater's gcc14/gcc14-libs exclusions.

Checks run on startup, hourly, and whenever the panel opens. No-update exit
codes are successful empty results; unavailable sources fail the refresh and
retain the previous valid status. The panel says “Updates available” whenever
the count is positive, and “Check failed” when a source cannot be checked.

`Service.qml` owns polling and service publication. `BarWidget.qml` is the bar
entry point. `UpdatePanelHost.qml` owns panel hosting and `UpdatePanel.qml`
owns the presentational update list.

## Logic boundaries

- `UpdateLogic.js` owns parsing, normalization, and severity mapping.
- `araneadev.shared/StatusRow.qml` owns the reusable status-row contract.
- QML owns composition and the host updater action.

## Validation

Run `bash tests/update-status.test.sh`,
`tests/qml-behaviour.test.sh updates-service updates-widget updates-dropdown`,
and `node tests/js/update-logic.test.js`.
