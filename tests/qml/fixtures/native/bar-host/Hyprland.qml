// Only compositor records are faked. Native windows and input remain real.
pragma Singleton
import QtQuick

QtObject {
  // Whether the private fullscreen sink is active.
  property bool fullscreen: false
  // Synthetic monitor records for the private output.
  property var focusedMonitor: ({
      activeWorkspace: {
        id: 1
      }
    })
  // The fullscreen bit consumed by the real bar input mask.
  property var toplevels: ({
      values: [
        {
          workspace: {
            id: 1
          },
          lastIpcObject: {
            fullscreen: fullscreen ? 2 : 0
          }
        }
      ]
    })
  // Native event boundary used by the production refresh connection.
  signal rawEvent(var event)
  // Return the private output monitor record.
  function monitorFor(screen) {
    return focusedMonitor
  }
  // No IPC is needed for these synchronous fixture records.
  function refreshToplevels() {
  }
}
