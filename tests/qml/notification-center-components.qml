// Behaviour contracts for notification center presentation components.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.notifications" as NotificationComponents

ShellRoot {
  QmlTest {
    id: t
  }

  NotificationComponents.NotificationCenterContent {
    id: content
    count: 2
    dnd: true
    confirmingClear: false
    quiet: true
    quietUntil: "18:00"
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
    t.equal(content.count, 2, "notification center exposes count")
    t.equal(content.dnd, true, "notification center exposes DND state")
    t.equal(list.rows.length, 1, "notification lists expose row models")
    t.equal(list.cursor, 0, "notification lists expose cursor state")
    t.done()
  }
}
