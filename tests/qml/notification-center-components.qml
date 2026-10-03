// Behaviour contracts for notification center presentation components.
// NotificationCenterContent's own view object and action contract are
// covered by tests/qml/notification-center-header.qml.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.notifications" as NotificationComponents

ShellRoot {
  QmlTest {
    id: t
  }

  NotificationComponents.NotificationList {
    id: list
    rows: [
      {
        kind: "more",
        app: "Chat",
        hidden: 2
      }
    ]
    cursor: 0
  }

  Component.onCompleted: {
    t.equal(list.rows.length, 1, "notification lists expose row models")
    t.equal(list.cursor, 0, "notification lists expose cursor state")
    t.done()
  }
}
