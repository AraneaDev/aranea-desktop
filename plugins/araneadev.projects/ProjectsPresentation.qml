// Persistent Projects presentation, independent of desktop Settings.
import QtQuick
import Quickshell.Io
import "../araneadev.activity" as Activity
import "ProjectsLogic.js" as Logic

Item {
  id: root
  // Scoped shell object injected by the plugin host.
  property var shell: null
  // Plugin manifest injected by the host.
  property var manifest: null
  // Whether to create the summoned window; offscreen fixtures leave it out.
  property bool windowEnabled: true
  // Owner-wide inert mode gates presentation clients as well as the operation owner.
  property bool captureActive: false
  // Scoped capture and external inert hosts share the same IO refusal boundary.
  readonly property bool inert: captureActive || !!captureSaved
  // Whether the host should display the Projects window.
  property bool opened: false
  // Current Projects destination retained for typed capture fixtures.
  property string section: 'projects'
  // Optional opaque details destination, empty for the Projects overview.
  property string projectId: ''
  // Registry/tool operation client works independently of the live owner.
  property alias projectController: projectController
  // Sole-owner submission/observation client, without launch authority.
  property alias projectClient: projectClient
  // Keep-loaded cancellable scan observer survives window visibility changes.
  property alias discoveryClient: discoveryClient
  ProjectRegistryClient {
    id: projectController
    captureActive: root.inert
  }
  ProjectClient {
    id: projectClient
    captureActive: root.inert
  }
  ProjectDiscoveryController {
    id: discoveryClient
    captureActive: root.inert
  }
  Connections {
    target: projectController
    function onRootReady(rootId) {
      discoveryClient.start(rootId)
    }
    function onMutationCompleted(action, args, state) {
      if (action === 'register') {
        var added = state.projects.filter(function (p) {
          return p.checkouts.some(function (c) {
            return args.paths.indexOf(c.path) >= 0
          })
        })[0]
        if (added)
          root.projectId = added.id
        discoveryClient.candidates = discoveryClient.candidates.filter(function (c) {
          return [c.path].concat((c.checkouts || []).map(function (checkout) {
            return checkout.path
          })).some(function (path) {
            return !state.projects.some(function (p) {
              return p.checkouts.some(function (checkout) {
                return checkout.path === path
              })
            })
          })
        })
      }
      if (action === 'remove' && root.projectId === args.projectId)
        root.projectId = ''
      if (action === 'ignore')
        discoveryClient.candidates = discoveryClient.candidates.filter(function (c) {
          return !state.ignored.some(function (i) {
            return i.commonDir === c.commonDir
          })
        })
    }
  }
  // Summoned window instance, independent of the persistent controller.
  property var view: null
  // Compatibility observation for capture fixtures; never owns desktop settings.
  property QtObject controller: QtObject {
    readonly property bool showcaseActive: root.inert
  }
  // Persistent activity observer; accepted task operations outlive the window.
  property alias activityClient: activityClient
  Activity.ActivityClient {
    id: activityClient
    captureActive: root.inert
  }
  Timer {
    interval: 5000
    running: root.opened && !!root.view && root.view.activityVisible && !root.inert
    repeat: true
    triggeredOnStart: true
    onTriggered: activityClient.refresh()
  }
  // Scoped inert capture state, with drafts restored to their exact identities.
  property var captureSaved: null
  // Serialize local presentation and observations without backend reads.
  function captureSnapshot() {
    return JSON.stringify({
      opened: opened,
      section: section,
      projectId: projectId,
      projects: {
        state: projectController.state,
        tools: projectController.tools,
        error: projectController.error,
        candidates: discoveryClient.candidates,
        partial: discoveryClient.partial,
        errors: discoveryClient.errors,
        snapshot: projectClient.snapshot,
        available: projectClient.available,
        clientError: projectClient.error,
        requestError: projectClient.requestError
      },
      activity: {
        snapshot: activityClient.snapshot,
        available: activityClient.available,
        error: activityClient.error
      },
      ui: view ? view.captureSnapshot() : null
    })
  }
  // Validate and enter an inert transaction before changing any observation.
  function captureBegin(payloadJson) {
    if (activityClient.pending || projectController.pending || projectController.reading || projectClient.pending || projectClient.preparing || discoveryClient.pending || captureSaved || (view && view.captureBusy()))
      return 'busy'
    var payload
    try {
      payload = JSON.parse(payloadJson)
    } catch (e) {
      return 'invalid'
    }
    if (!payload || payload.snapshot !== captureSnapshot() || !payload.fixture || !payload.fixture.projectsState || !Array.isArray(payload.fixture.projectsState.roots) || !Array.isArray(payload.fixture.projectsState.ignored) || !Array.isArray(payload.fixture.projectsState.projects) || (payload.section !== undefined && payload.section !== 'projects') || (payload.projectId !== undefined && payload.projectId !== '' && Logic.normalizeProjectId(payload.projectId) !== payload.projectId) || (payload.fixture.projectCandidates !== undefined && !Array.isArray(payload.fixture.projectCandidates)))
      return 'invalid'
    captureSaved = {
      json: payload.snapshot,
      focus: view ? view.captureFocus() : null
    }
    projectId = Logic.normalizeProjectId(payload.projectId)
    var f = payload.fixture
    activityClient.snapshot = f.activitySnapshot || {
      tasks: [],
      operations: []
    }
    activityClient.available = false
    activityClient.error = null
    projectController.state = f.projectsState
    projectController.tools = f.projectTools || {
      defaults: {},
      editors: [],
      terminals: []
    }
    projectController.error = f.projectError || ''
    discoveryClient.candidates = f.projectCandidates || []
    discoveryClient.partial = f.projectPartial === true
    discoveryClient.errors = f.projectErrors || []
    projectClient.snapshot = f.projectSnapshot || {}
    projectClient.available = f.projectAvailable === true
    projectClient.error = ''
    projectClient.requestError = null
    if (view)
      view.captureReset(f)
    opened = true
    return 'ok'
  }
  // Expose explicit read-only and settled-render readiness for capture callers.
  function captureState() {
    return JSON.stringify({
      readOnly: !!captureSaved,
      ready: !!captureSaved && opened && !!view && view.captureReady()
    })
  }
  // Restore only capture-owned state and retained drafts by exact identity.
  function captureRestore(payloadJson) {
    if (!captureSaved || payloadJson !== captureSaved.json)
      return 'invalid'
    var saved = JSON.parse(payloadJson), focus = captureSaved.focus, p = saved.projects
    activityClient.snapshot = saved.activity.snapshot
    activityClient.available = saved.activity.available
    activityClient.error = saved.activity.error
    projectController.state = p.state
    projectController.tools = p.tools
    projectController.error = p.error
    discoveryClient.candidates = p.candidates
    discoveryClient.partial = p.partial
    discoveryClient.errors = p.errors
    projectClient.snapshot = p.snapshot
    projectClient.available = p.available
    projectClient.error = p.clientError
    projectClient.requestError = p.requestError
    projectId = saved.projectId
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
    target: 'aranea.projects.capture'
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
  // Accept a typed destination and refresh observations without launching tools.
  function open(payloadJson) {
    if (inert)
      return 'busy'
    var payload = {}
    try {
      payload = JSON.parse(payloadJson || '{}')
    } catch (e) {}
    var nextId = payload && payload.projectId !== undefined ? Logic.normalizeProjectId(payload.projectId) : projectId
    if (view && nextId !== projectId && view.navigationBlocked)
      return 'busy'
    projectId = nextId
    opened = true
    projectController.refresh()
    projectClient.refresh()
    if (view)
      view.focusKeys()
    return 'ok'
  }
  // Hide presentation while retaining drafts and accepted service operations.
  function close() {
    opened = false
  }
  Component.onCompleted: {
    if (!windowEnabled)
      return
    var component = Qt.createComponent(Qt.resolvedUrl('ProjectsWindow.qml'))
    if (component.status === Component.Ready)
      view = component.createObject(root, {
        root: root
      })
    else
      console.warn('projects: window failed to load:', component.errorString())
  }
}
