# Aranea notifications

`araneadev.notifications` provides notification ingestion, popups, DND, an
inbox, and the notification-center bar widget. The manifest exposes
`Service.qml` and `Panel.qml` and keeps the service loaded.

## Responsibilities

- Receive and normalize desktop notifications.
- Persist inbox entries and image data safely.
- Render grouped notifications, progress, dismissal, and action rows.
- Enforce quiet hours and DND policy.
- Publish popup and bar state through the notification service bridge.

`Service.qml` owns the daemon and service lifecycle. `Toasts.qml` owns popup
placement, `Inbox.qml` owns the inbox surface, and `Panel.qml` owns the bar
entry point. The components directory contains presentational cards and group
rows.

## Logic boundaries

- `NotificationLogic.js` owns normalization, persistence, quiet hours, and
  popup policy.
- `NotificationSettings.js` owns persisted settings.
- `NotificationPresentation.js` owns display projections.
- `InboxLogic.js` owns inbox-specific state.
- `ServiceBridge.js` publishes the current service through shared registry
  infrastructure.

## Validation

Run `tests/qml-behaviour.test.sh notification-components notification-center-components notifications`
and the notification JS suites.
