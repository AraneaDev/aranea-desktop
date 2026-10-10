// Serial projection of shared logical typography into desktop applications.
import QtQuick
import Quickshell.Io

Item {
  id: sync
  // Only the owning desktop shell enables application mutations.
  enabled: false
  // Effective interface family supplied by the typography owner.
  property string family: ''
  // Logical body pixels, after theme and machine overrides.
  property int bodyPixels: 0
  // Active theme helper, injectable for isolated tests.
  property string adapterPath: RuntimePaths.themeRoot + '/scripts/aranea-sync-desktop-font'
  // Whether the previous projection is still running.
  property bool pending: false
  // Latest successfully projected argument snapshot.
  property string applied: ''
  // Desktop scaling notifications invalidate even an unchanged logical size.
  property int revision: 0
  // Process boundary with an injectable completion callback.
  property var runner: function (argv, done) {
    var process = processComponent.createObject(sync, {
      command: argv,
      completion: done
    })
    process.startRequested = true
    process.running = true
  }
  // Coalesce startup reads and simultaneous family/size changes.
  function schedule(): void {
    if (enabled)
      debounce.restart()
    else
      debounce.stop()
  }
  // Reproject after external GTK scaling changes, including repeated size commands.
  function invalidate(): void {
    revision++
    schedule()
  }
  // Serialize writes and apply the latest state after any in-flight update.
  function apply(): void {
    if (!enabled || pending || !family || bodyPixels <= 0)
      return
    var argv = [adapterPath, family, String(bodyPixels)]
    var snapshot = JSON.stringify([argv, revision])
    if (snapshot === applied)
      return
    pending = true
    runner(argv, function (exitCode) {
      pending = false
      if (exitCode === 0) {
        applied = snapshot
        schedule()
      } else {
        if (JSON.stringify([[adapterPath, family, String(bodyPixels)], revision]) !== snapshot)
          schedule()
        console.warn('Aranea desktop font synchronization failed; shared shell typography remains available.')
      }
    })
  }
  onEnabledChanged: schedule()
  onFamilyChanged: schedule()
  onBodyPixelsChanged: schedule()
  Component.onCompleted: schedule()
  Timer {
    id: debounce
    interval: 150
    onTriggered: sync.apply()
  }
  Component {
    id: processComponent
    Process {
      id: process
      // Completion owned by the projection that created this process.
      property var completion: null
      // Track failed starts, which emit no exit signal.
      property bool startRequested: false
      // An exit after a successful launch must complete through onExited.
      property bool startedSuccessfully: false
      // Complete at most once across launch failure and exit callbacks.
      property bool completed: false
      // Release the in-flight projection on every completion path.
      function finish(exitCode): void {
        if (completed)
          return
        completed = true
        if (completion)
          completion(exitCode)
        process.destroy()
      }
      onStarted: process.startedSuccessfully = true
      onRunningChanged: if (startRequested && !running && !startedSuccessfully)
        process.finish(-1)
      // Quickshell exposes an unregistered QProcess::ExitStatus parameter to qmllint.
      // qmllint disable signal-handler-parameters
      onExited: function (exitCode) {
        process.finish(exitCode)
      }
      // qmllint enable signal-handler-parameters
    }
  }
}
