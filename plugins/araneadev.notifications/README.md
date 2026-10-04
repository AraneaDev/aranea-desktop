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

## The center

The center draws in the shared `Aranea.KeyboardPanelFrame`: a Filament header
(`NotificationCenterContent.qml`: caption, "Do not disturb" switch, the list in
its slot, the "Clear all" pill and the key hint) around `NotificationList.qml`.

Keys:

- Up/Down (or k/j) move the cursor through its stops, top to bottom: the
  "Do not disturb" switch, every entry and "+N more" row, then the "Clear
  all" pill. The cursor stops at both ends. Group headers are not stops.
- Left/Right (or h/l) only reveal the cursor.
- Enter or Space acts on the cursor: an entry opens, "+N more" expands its
  group, the switch toggles DND, the pill clears (two steps above 20 entries).
- Delete or x dismisses the entry under the cursor (on "+N more" it expands
  first); Shift+Delete clears the entry's whole app group.
- Esc closes; Tab and Shift+Tab switch to the next panel.

The key hint line follows the state (`InboxLogic.centerKeyHint`): "↑↓ move
· enter open · x dismiss · ⇧del group" with entries and "↑↓ move · enter
toggle" when the center is empty. Like every dropdown hint, it leaves out
Tab (next dropdown) so the Enter verb fits.

The cursor is keyboard-only. A fresh open shows none; the first key
(Enter included) only reveals it, and any pointer click hides it. It
follows its entry by key across re-sorts and hides when that entry goes. A
real pointer move over a card, a group header or "+N more" draws the shared
hover fill there; it never moves the cursor or the outline.

The DND switch shows the new state at once and pulses until the service
echoes it. Clicks made while it waits are queued and the last one wins
(`InboxLogic.dndClick`, `dndEcho` and `dndView`). If the service never echoes a
change within 3 s, the switch gives up and shows the service's state again;
a click queued behind that change is dropped. The "+N more" row keeps its
12 px left padding, so its text lines up with the cards' content.

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
