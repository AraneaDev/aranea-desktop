// Native compositor boundary for the notification service behavior fixture.
pragma Singleton
import QtQuick

QtObject {
  // Current native window records supplied at the compositor boundary.
  property var toplevels: ({
      values: []
    })
  // Dispatches observed at the native compositor boundary.
  property var dispatched: []
  // Record a native dispatch without contacting any compositor.
  function dispatch(command) {
    dispatched = dispatched.concat([command])
  }
}
