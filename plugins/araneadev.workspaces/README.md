# Aranea workspaces

Horizontal bars show a bounded project-name inspection label for a focused
workspace with one launched environment or a checkout confirmed by a verified
tool in the current session. Launched environments retain their context across
shell restarts, with unconfirmed tools noted in the tooltip. A bare saved
workspace assignment alone does not show a bar label.
Full context stays in its tooltip, including branch and launch-time context;
ambiguous or unavailable context falls back to the workspace controls.
The overview still shows saved assignments as project context.
The bar polls the existing read-only project client every five seconds while
visible, with serialized reads and capture refusal. Clicking the label summons
Projects with exact project and checkout IDs, without launching tools.

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
hosting and `WorkspacePanel.qml` owns the overview composition, in the
Filament look: an `Aranea.DropdownHeader` and one `Aranea.NodeDeviceRow` per
workspace, keyed by workspace id.

## Logic boundaries

- `WorkspaceModel.js` owns normalization, visibility, labels, and navigation
  targets.
- QML owns compositor interaction and visual composition.
- Shared components own only reusable visual contracts.

## Validation

Run `tests/qml-behaviour.test.sh workspaces-widget workspaces-keyed panel-heights`
and the workspace JS suite.
