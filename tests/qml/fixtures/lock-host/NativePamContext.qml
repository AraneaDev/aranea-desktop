// Inert PAM boundary: no host authentication conversation can be started.
import QtQuick

QtObject {
  // Accepts the production PAM service name.
  property string config: ""
  // Accepts the production username.
  property string user: ""
  // Reports no active conversation.
  property bool active: false
  // Reports no pending prompt.
  property bool responseRequired: false
  // Mirrors the native result event.
  signal completed(var result)
  // Mirrors the native failure event.
  signal error(var error)
  // Mirrors the native message event.
  signal pamMessage
  // Refuses authentication at the system boundary.
  function start() {
    return false
  }
  // Clears any simulated conversation.
  function abort() {
    active = false
  }
  // Accepts a response without passing it to the operating system.
  function respond(value) {
  }
}
