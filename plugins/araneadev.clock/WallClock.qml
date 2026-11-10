// Epoch-aligned replacement for SystemClock: DST folds never produce negative delays.
import QtQuick
import "Model.js" as Model

Timer {
  id: root

  // Milliseconds between ticks: 1000 for seconds, 60000 for minutes.
  property int step: 60000
  // Current local date, advanced from epoch time at every tick or explicit refresh.
  property date date: new Date()

  // Restarts at the next epoch boundary, independent of local timezone transitions.
  function arm() {
    interval = Model.msUntilNextTick(Date.now(), step)
    restart()
  }

  // Re-reads the current date and realigns the next tick after explicit updates.
  function refresh() {
    date = new Date()
    arm()
  }

  onStepChanged: arm()
  onTriggered: refresh()
  Component.onCompleted: refresh()
}
