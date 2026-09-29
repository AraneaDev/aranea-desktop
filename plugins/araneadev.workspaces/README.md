# Aranea workspaces

`araneadev.workspaces` is the compact workspace bar widget. Its manifest
exposes `BarWidget.qml` and places the widget in the left bar section by
default.

## Responsibilities

- Normalize Hyprland workspace and toplevel data.
- Show active, occupied, urgent, special, and standard workspaces.
- Focus a workspace, cycle visible workspaces, and open the overview panel.
- Keep the bar indicator compact while exposing meaningful workspace labels in
  the overview.

`BarWidget.qml` is the bar entry point. `WorkspacePanelHost.qml` owns panel
hosting and `WorkspacePanel.qml` owns the overview composition. The shared
`StatusRow` provides the status-row contract for the panel.

## Logic boundaries

- `WorkspaceModel.js` owns normalization, visibility, labels, and navigation
  targets.
- QML owns compositor interaction and visual composition.
- Shared components own only reusable visual contracts.

## Validation

Run `tests/qml-behaviour.test.sh workspaces-widget` and the workspace JS suite.
