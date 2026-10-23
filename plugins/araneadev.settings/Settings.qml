// Keep-loaded settings plugin lifecycle entry.
import QtQuick
import Quickshell.Io
import "SettingsLogic.js" as Logic
import "../araneadev.shared" as Aranea

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
  property alias controller: controllerObject
  // Injected process boundary taking argv and an exit/stdout/stderr callback.
  property alias runner: controllerObject.runner
  // Backend executable, resolved from the active theme root by default.
  property alias adapterPath: controllerObject.adapterPath
  SettingsController {
    id: controllerObject
  }
  // Session-only read boundary; never changes the saved selection or idle timers.
  property string previewSessionPath: Aranea.RuntimePaths.themeRoot + '/scripts/aranea-screensaver'
  // Return only from a preview launched by this open picker.
  property bool previewReturn: false
  // Exact accepted session identity; no PID or global process matching.
  property string previewSessionId: ''
  // Serialize observation and discard callbacks after manual open/close.
  property bool previewPolling: false
  // Invalidate asynchronous reads after a different presentation request.
  property int previewGeneration: 0
  // Cancel observation without stopping or changing any screensaver session.
  function cancelPreviewReturn() {
    previewGeneration++
    previewReturn = false
    previewSessionId = ''
    previewPolling = false
  }
  // Return only after a current unlocked observation, including refused launches.
  function returnFromPreview() {
    if (!previewReturn || previewPolling)
      return
    var generation = previewGeneration
    previewPolling = true
    controllerObject.runCommand([controllerObject.notificationsPath, 'lock', 'isLocked'], function (code, state, stderr) {
      if (generation !== previewGeneration)
        return
      previewPolling = false
      if (code !== 0 || ['true', 'false'].indexOf(state.trim()) < 0)
        return
      var restore = state.trim() === 'false'
      cancelPreviewReturn()
      if (restore) {
        opened = true
        if (view)
          view.focusKeys()
      }
    })
  }
  // Observe only the accepted session; unreadable observations never steal focus.
  function pollPreview() {
    if (!previewReturn || previewPolling || controllerObject.pending)
      return
    if (!previewSessionId) {
      returnFromPreview()
      return
    }
    var generation = previewGeneration
    previewPolling = true
    controllerObject.runCommand([previewSessionPath, 'session', '--json'], function (code, stdout, stderr) {
      if (generation !== previewGeneration)
        return
      var session = null
      try {
        let value = JSON.parse(stdout)
        session = value && value.session
      } catch (e) {}
      if (code !== 0 || !session || typeof session.running !== 'boolean') {
        previewPolling = false
        return
      }
      if (session.sessionId !== previewSessionId) {
        cancelPreviewReturn()
        return
      }
      if (session.running) {
        previewPolling = false
        return
      }
      if (session.sessionId === previewSessionId)
        controllerObject.state = Object.assign({}, controllerObject.state, {
          screensaver: Object.assign({}, controllerObject.state.screensaver || {}, {
            session: session
          })
        })
      previewPolling = false
      returnFromPreview()
    })
  }
  Timer {
    interval: 750
    repeat: true
    running: root.previewReturn
    onTriggered: root.pollPreview()
  }
  Connections {
    target: controllerObject
    function onPreviewRequested() {
      root.cancelPreviewReturn()
      root.previewReturn = root.opened
      root.opened = false
    }
    function onPreviewAccepted(sessionId) {
      // A delegated stock preview has no owned identity to observe.
      if (sessionId)
        root.previewSessionId = sessionId
      else
        root.cancelPreviewReturn()
    }
    function onMutationCompleted(operation, args, succeeded) {
      if (operation === 'preview screensaver' && !succeeded)
        root.returnFromPreview()
    }
  }
  // Internal transaction state; JSON snapshots cannot overwrite arbitrary owner data.
  property var captureSaved: null
  // Serialize current presentation and prior showcase observations without reading owners.
  function captureSnapshot() {
    return JSON.stringify({
      opened: opened,
      section: section,
      ui: view ? view.captureSnapshot() : null,
      showcase: controllerObject.showcaseActive,
      fixture: {
        state: controllerObject.state,
        error: controllerObject.error,
        notifications: controllerObject.notifications,
        notificationErrors: controllerObject.notificationErrors,
        results: controllerObject.results,
        itemErrors: controllerObject.itemErrors
      }
    })
  }
  // Atomically accept an inert fixture before changing visibility or presentation.
  function captureBegin(payloadJson) {
    if (previewReturn || controllerObject.pending || captureSaved || (view && typeof view.captureBusy === 'function' && view.captureBusy()))
      return 'busy'
    var payload
    try {
      payload = JSON.parse(payloadJson)
    } catch (e) {
      return 'invalid'
    }
    if (!payload || ['appearance', 'display', 'schedule', 'screensavers'].indexOf(payload.section) < 0)
      return 'invalid'
    if (payload.fixture && payload.fixture.displayDraft && (typeof payload.fixture.displayDraft !== 'string' || !Logic.validateScale(payload.fixture.displayDraft).ok))
      return 'invalid'
    var saved = captureSnapshot()
    if (payload.snapshot !== saved)
      return 'invalid'
    var focus = view && typeof view.captureFocus === 'function' ? view.captureFocus() : null
    var result = controllerObject.beginShowcase(payload.fixture)
    if (result !== 'ok')
      return result
    captureSaved = {
      json: saved,
      ownerSaved: controllerObject.showcaseSaved,
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
      readOnly: !!captureSaved && controllerObject.showcaseActive && !controllerObject.pending,
      ready: !!captureSaved && opened && !!view && view.captureReady()
    })
  }
  // Restore only the snapshot belonging to this capture, including a prior showcase.
  function captureRestore(payloadJson) {
    if (!captureSaved || payloadJson !== captureSaved.json)
      return 'invalid'
    var saved = JSON.parse(captureSaved.json)
    var focus = captureSaved.focus
    controllerObject.endShowcase()
    if (saved.showcase) {
      controllerObject.beginShowcase(saved.fixture)
      controllerObject.showcaseSaved = captureSaved.ownerSaved
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
    return controllerObject.beginShowcase(fixture)
  }
  // Open a supported payload destination and refresh owner state.
  function open(payloadJson) {
    if (captureSaved)
      return 'busy'
    var payload = ({})
    try {
      payload = JSON.parse(payloadJson || '{}')
    } catch (e) {}
    cancelPreviewReturn()
    section = Logic.normalizeSection(payload && payload.section)
    opened = true
    controllerObject.reopened()
    if (view)
      view.focusKeys()
  }
  // Hide the window without cancelling owned processes.
  function close() {
    cancelPreviewReturn()
    opened = false
    controllerObject.endShowcase()
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
