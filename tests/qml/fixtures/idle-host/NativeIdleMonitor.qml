// Offscreen boundary only: upstream Service owns every timer and transition.
import QtQuick

QtObject {
  // Native monitoring enablement consumed by upstream bindings.
  property bool enabled: false
  // Requested native idle threshold in seconds.
  property int timeout: 1
  // Preserve the upstream native inhibition setting.
  property bool respectInhibitors: true
  // Controlled native activity boundary; service timers stay real.
  property bool isIdle: false
}
