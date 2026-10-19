// Installable reload adapter for stock Omarchy's cached plugin recreation.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: controller
  // Only the bar in the owning desktop shell starts the watcher; previews stay inert.
  property bool active: false
  // Installed plugin tree watched for source changes.
  property string pluginRoot: Quickshell.env('HOME') + '/.config/omarchy/plugins'
  // Quiet period used to coalesce an installer or editor burst.
  property int settleInterval: 250
  // An observed change still needs a native engine reload.
  property bool pending: false
  // A native reload is currently handing over to a new engine.
  property bool reloading: false
  // Authentication owners must all report idle before reloading.
  readonly property bool blocked: PluginReloadState.blocked
  // Tracks responsibility for Quickshell automatic watching.
  property bool ownsWatcher: false

  // Transfers file watching between this adapter and Quickshell.
  function configureWatcher(): void {
    if (active) {
      ownsWatcher = true
      Quickshell.watchFiles = false
    } else if (ownsWatcher) {
      ownsWatcher = false
      Quickshell.watchFiles = true
      pending = false
      settle.stop()
    }
  }

  // Queues relevant source edits while ignoring hidden metadata.
  function changed(path: string): void {
    if (!active || path.indexOf(pluginRoot + '/') !== 0)
      return
    var parts = path.slice(pluginRoot.length + 1).split('/')
    if (parts.some(function (part) {
      return part.charAt(0) === '.'
    }))
      return
    request()
  }

  // Retains a reload request even while authentication is active.
  function request(): void {
    if (!active)
      return
    pending = true
    schedule()
  }

  // Starts the debounce only when every reload guard is ready.
  function schedule(): void {
    if (active && pending && !blocked && !reloading)
      settle.restart()
  }

  onActiveChanged: configureWatcher()
  onBlockedChanged: schedule()
  Component.onCompleted: configureWatcher()
  Component.onDestruction: if (ownsWatcher && !reloading)
    Quickshell.watchFiles = true

  Process {
    id: watcher
    running: controller.active
    command: ['inotifywait', '-m', '-r', '-q', '-e', 'close_write,create,delete,move', '--format', '%w%f', controller.pluginRoot]
    stdout: SplitParser {
      onRead: function (path) {
        controller.changed(path)
      }
    }
  }

  Timer {
    id: settle
    interval: controller.settleInterval
    onTriggered: {
      if (!controller.active || !controller.pending || controller.blocked || controller.reloading)
        return
      controller.pending = false
      controller.reloading = true
      Quickshell.reload(false)
    }
  }

  Connections {
    target: Quickshell
    function onReloadCompleted() {
      // Reassert ownership after a successful engine handoff.
      controller.configureWatcher()
    }
    function onReloadFailed(errorString) {
      controller.reloading = false
      console.warn('Aranea plugin reload failed; keeping the current shell:', errorString)
    }
  }

  IpcHandler {
    enabled: controller.active
    target: 'aranea.reload'
    function reload(): string {
      controller.request()
      return controller.blocked ? 'deferred' : 'queued'
    }
    function status(): string {
      return JSON.stringify({
        pending: controller.pending,
        blocked: controller.blocked,
        reloading: controller.reloading
      })
    }
  }
}
