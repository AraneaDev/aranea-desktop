// Keep-loaded audio default-device owner; panels and search share its identity.
import QtQuick
import "AudioBridge.js" as Bridge

Item {
  id: service
  // Scoped shell injected by the plugin host.
  property var shell: null
  // Default-device controller shared by all consumers.
  property alias defaults: defaultsObject
  AudioDefaults {
    id: defaultsObject
  }
  Component.onCompleted: Bridge.publish(defaultsObject)
  Component.onDestruction: Bridge.retract(defaultsObject)
}
