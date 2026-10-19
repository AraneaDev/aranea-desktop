//@ pragma OmarchyLoadPatch
import QtQuick
import Quickshell
import Quickshell.Io
import "plugins/araneadev.shared" as Aranea
import "plugins/fixture.auth" as Auth

ShellRoot {
  id: host
  // Loaded fixture whose source and imported JavaScript change.
  property var instance: null
  // Distinguishes native engine generations within the same process.
  readonly property string generation: Date.now() + "-" + Math.random()
  Auth.AuthOwners {
    id: owners
  }
  Aranea.PluginReloadController {
    id: reloader
    active: true
    pluginRoot: Quickshell.env("ARANEA_RELOAD_TEST_PLUGIN_ROOT")
    settleInterval: 40
  }

  Component.onCompleted: {
    var component = Qt.createComponent('file://' + reloader.pluginRoot + '/example.test/Entry.qml')
    instance = component.createObject(host)
  }
  IpcHandler {
    target: 'aranea.reload-test'
    function state(): string {
      return JSON.stringify({
        marker: host.instance ? host.instance.marker : '',
        pid: Quickshell.processId,
        generation: host.generation,
        pending: reloader.pending,
        blocked: reloader.blocked,
        watchFiles: Quickshell.watchFiles
      })
    }
    function promptReady(value: bool): void {
      owners.promptReady = value
    }
    function lock(value: bool): void {
      owners.locked = value
    }
    function authenticate(value: bool): void {
      owners.authenticating = value
    }
  }
}
