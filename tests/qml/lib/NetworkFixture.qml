// Only the external command boundary is fake; production QML owns all state.
import QtQuick
import Quickshell.Io

Item {
  id: root
  // Latest complete snapshot from the sandbox command boundary.
  property var state: ({})
  // Continuation for the current fixture configuration.
  property var configured: null
  // Configure external command responses without changing production QML.
  function configure(options, callback) {
    configured = callback
    config.command = ["network-fixture", "configure", JSON.stringify(options)]
    config.running = true
  }
  Process {
    id: config
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.state = JSON.parse(text)
        var callback = root.configured
        root.configured = null
        if (callback)
          callback()
      }
    }
  }
  Process {
    id: snapshot
    command: ["network-fixture", "snapshot"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.state = JSON.parse(text)
    }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: if (!snapshot.running && !config.running)
      snapshot.running = true
  }
}
