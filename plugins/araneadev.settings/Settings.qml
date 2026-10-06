// Keep-loaded settings plugin lifecycle entry.
import QtQuick
import "SettingsLogic.js" as Logic

Item {
  id: root
  // Scoped shell object injected by the plugin host.
  property var shell: null
  // Plugin manifest injected by the host.
  property var manifest: null
  // Whether to create the summoned window; offscreen fixtures leave it out.
  property bool windowEnabled: true
  // Whether the host should display the settings window.
  property bool opened: false
  // Current supported settings destination.
  property string section: 'appearance'
  // Summoned window instance, independent of the persistent controller.
  property var view: null
  // Persistent settings process and state owner.
  property alias controller: controller
  // Injected process boundary taking argv and an exit/stdout/stderr callback.
  property alias runner: controller.runner
  // Backend executable, resolved from the active theme root by default.
  property alias adapterPath: controller.adapterPath
  SettingsController {
    id: controller
  }
  // Accept display-only snapshot JSON; owned mutations and malformed data refuse it.
  function showcase(payloadJson) {
    var fixture
    try {
      fixture = JSON.parse(payloadJson || '{}')
    } catch (e) {
      return 'invalid'
    }
    return controller.beginShowcase(fixture)
  }
  // Open a supported payload destination and refresh owner state.
  function open(payloadJson) {
    var payload = ({})
    try {
      payload = JSON.parse(payloadJson || '{}')
    } catch (e) {}
    section = Logic.normalizeSection(payload && payload.section)
    opened = true
    controller.reopened()
    if (view)
      view.focusKeys()
  }
  // Hide the window without cancelling owned processes.
  function close() {
    opened = false
    controller.endShowcase()
  }
  Component.onCompleted: {
    if (!windowEnabled)
      return
    var component = Qt.createComponent(Qt.resolvedUrl('SettingsWindow.qml'))
    if (component.status === Component.Ready)
      view = component.createObject(root, {
        root: root
      })
    else
      console.warn('settings: window failed to load:', component.errorString())
  }
}
