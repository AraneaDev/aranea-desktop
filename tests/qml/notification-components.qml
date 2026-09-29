// Behaviour contract for presentational notification components.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.notifications/components" as NotificationComponents

ShellRoot {
  QmlTest {
    id: t
  }

  NotificationComponents.NotificationGroupRow {
    id: row
    app: "Chat"
    count: 3
    collapsed: true
  }

  Component.onCompleted: {
    t.equal(row.app, "Chat", "notification groups expose their app")
    t.equal(row.count, 3, "notification groups expose their count")
    t.equal(row.collapsed, true, "notification groups expose collapsed state")
    t.done()
  }
}
