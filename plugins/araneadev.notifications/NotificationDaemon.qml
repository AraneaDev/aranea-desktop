// The freedesktop notification server on the session bus. Service.qml
// creates it with itself as `root` unless serverEnabled is off (tests), so a
// test never takes over the desktop's notifications.

import Quickshell.Services.Notifications

NotificationServer {
  id: server

  // The notification service (Service.qml) that handles each notification.
  required property var root

  keepOnReload: false
  imageSupported: true
  actionsSupported: true
  bodyMarkupSupported: true
  bodyHyperlinksSupported: true
  persistenceSupported: true

  onNotification: function (notification) {
    server.root.handleNotification(notification)
  }
}
