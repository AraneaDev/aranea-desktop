// Keep-loaded settings plugin lifecycle entry.
import QtQuick
import Quickshell.Io
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
  // Internal transaction state; JSON snapshots cannot overwrite arbitrary owner data.
  property var captureSaved: null
  // Serialize current presentation and prior showcase observations without reading owners.
  function captureSnapshot() {
    return JSON.stringify({
      opened: opened,
      section: section,
      ui: view ? view.captureSnapshot() : null,
      showcase: controller.showcaseActive,
      fixture: {
        state: controller.state,
        error: controller.error,
        notifications: controller.notifications,
        notificationErrors: controller.notificationErrors,
        results: controller.results,
        itemErrors: controller.itemErrors
      }
    })
  }
  // Atomically accept an inert fixture before changing visibility or presentation.
  function captureBegin(payloadJson) {
    if (controller.pending || captureSaved)
      return 'busy'
    var payload
    try {
      payload = JSON.parse(payloadJson)
    } catch (e) {
      return 'invalid'
    }
    if (!payload || ['appearance', 'display'].indexOf(payload.section) < 0)
      return 'invalid'
    if (payload.fixture && payload.fixture.displayDraft && (typeof payload.fixture.displayDraft !== 'string' || !Logic.validateScale(payload.fixture.displayDraft).ok))
      return 'invalid'
    var saved = captureSnapshot()
    if (payload.snapshot !== saved)
      return 'invalid'
    var focus = view && typeof view.captureFocus === 'function' ? view.captureFocus() : null
    var result = controller.beginShowcase(payload.fixture)
    if (result !== 'ok')
      return result
    captureSaved = {
      json: saved,
      ownerSaved: controller.showcaseSaved,
      focus: focus
    }
    section = payload.section
    if (view)
      view.captureReset(payload.fixture)
    opened = true
    return 'ok'
  }
  // Report explicitly inert readiness; capture callers must check both flags.
  function captureState() {
    return JSON.stringify({
      readOnly: !!captureSaved && controller.showcaseActive && !controller.pending,
      ready: !!captureSaved && opened && !!view && view.captureReady()
    })
  }
  // Restore only the snapshot belonging to this capture, including a prior showcase.
  function captureRestore(payloadJson) {
    if (!captureSaved || payloadJson !== captureSaved.json)
      return 'invalid'
    var saved = JSON.parse(captureSaved.json)
    var focus = captureSaved.focus
    controller.endShowcase()
    if (saved.showcase) {
      controller.beginShowcase(saved.fixture)
      controller.showcaseSaved = captureSaved.ownerSaved
    }
    section = saved.section
    opened = saved.opened
    if (view && saved.ui)
      view.captureRestore(saved.ui)
    captureSaved = null
    if (opened && focus)
      Qt.callLater(function () {
        focus.forceActiveFocus()
      })
    return 'ok'
  }
  IpcHandler {
    target: 'aranea.settings.capture'
    function captureSnapshot(): string {
      return root.captureSnapshot()
    }
    function captureBegin(payload: string): string {
      return root.captureBegin(payload)
    }
    function captureState(): string {
      return root.captureState()
    }
    function captureRestore(payload: string): string {
      return root.captureRestore(payload)
    }
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
