// Inert compositor lock boundary; production ownership and timers stay real.
import QtQuick

Item {
  // Tracks a requested native lock without contacting the compositor.
  property bool locked: false
  // Tests never simulate a secure compositor or begin fingerprint PAM.
  property bool secure: false
  // Matches the native session-lock state event.
  signal lockStateChanged
  // Matches the native session-lock secure event.
  signal secureStateChanged
  onLockedChanged: lockStateChanged()
  onSecureChanged: secureStateChanged()
}
