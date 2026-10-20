// Persistent Projects presentation, independent of desktop Settings.
import QtQuick
import Quickshell.Io
import "../araneadev.activity" as Activity
import "ProjectsLogic.js" as Logic
import "ProjectsNavigation.js" as Navigation

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
  // Layout of the window: empty for the full Projects layout, or the compact quick switcher.
  property string mode: ''
  // Closing the window ends every automatic check; they only ever read.
  onOpenedChanged: if (!opened) {
    projectClientObject.stopAutoCheck()
    actionClientObject.stopAutoCheck()
  }
  // Current Projects destination retained for typed capture fixtures.
  property string section: 'projects'
  // Optional opaque details destination, empty for the Projects overview.
  property string projectId: ''
  // Inspection can select an exact checkout without changing saved launch preferences.
  property string inspectionCheckoutId: ''
  // External inspection waits for registry readback and the production draft guards.
  property var inspectionDestination: null
  // Missing external destinations never silently substitute another worktree.
  property string inspectionError: ''
  // Explicit profile Start may first select its inspected checkout in the registry.
  property var inspectionLaunchIntent: null
  // Presentation-only checkout selection is shared by header, actions, Git and agents.
  readonly property var presentationState: Object.assign({}, projectControllerObject.state, {
    projects: (projectControllerObject.state.projects || []).map(function (project) {
      return project.id === root.projectId && root.inspectionCheckoutId ? Object.assign({}, project, {
        lastCheckoutId: root.inspectionCheckoutId
      }) : project
    })
  })
  // Every genuine selection source records once; fixture changes remain inert.
  onProjectIdChanged: {
    inspectionCheckoutId = ''
    clearDismissalIntent()
    if (projectId && !inert)
      rememberNavigation(projectId, undefined, true)
  }
  // Restore saved registration only after the initial registry observation.
  property bool restoreNavigationPending: false
  // Restoration is presentation-only and never asks the live owner to Open.
  function restoreNavigation() {
    if (!restoreNavigationPending || inert || projectControllerObject.reading)
      return
    var state = projectControllerObject.state
    projectId = Navigation.restoreSelection(state.projects || [], projectId || null, (state.navigation || {}).lastProjectId || null)
    restoreNavigationPending = false
  }
  // Metadata writes have no authority over project inspection or draft guards.
  property bool navigationSaving: false
  // Retain later visits and pin changes while the registry serializes mutations.
  property var navigationQueue: []
  // Queue exact-ID metadata without waiting for storage to accept inspection.
  function rememberNavigation(id, pinned, deferred) {
    if (inert || !id)
      return
    var args = pinned === undefined ? {
      projectId: id,
      visit: true
    } : {
      projectId: id,
      pinned: pinned
    }
    navigationQueue = navigationQueue.concat([args])
    if (deferred)
      Qt.callLater(flushNavigation)
    else
      flushNavigation()
  }
  // Drain metadata only when existing registry work has completed; failures are final.
  function flushNavigation() {
    if (inert || projectControllerObject.pending || projectControllerObject.reading || !navigationQueue.length)
      return
    var args = navigationQueue[0]
    navigationQueue = navigationQueue.slice(1)
    if (!(projectControllerObject.state.projects || []).some(function (project) {
      return project.id === args.projectId
    })) {
      Qt.callLater(flushNavigation)
      return
    }
    navigationSaving = true
    if (!projectControllerObject.request('navigation-set', args))
      navigationSaving = false
  }
  // Registry/tool operation client works independently of the live owner.
  property alias projectController: projectControllerObject
  // Sole-owner submission/observation client, without launch authority.
  property alias projectClient: projectClientObject
  // Keep-loaded cancellable scan observer survives window visibility changes.
  property alias discoveryClient: discoveryClientObject
  // Read-only Git cache survives visibility while launch ownership stays separate.
  property alias gitClient: gitClientObject
  // Explicit fetch, pull and task-checkout commands share one slot.
  property alias gitCommands: gitCommands
  // Invalid or missing selected checkouts never fall back to another worktree.
  readonly property var selectedProject: (presentationState.projects || []).filter(function (project) {
    return project.id === root.projectId
  })[0] || null
  // Dismissal belongs to one visible user action, never to observation lifetime.
  property string awaitedLaunchId: ''
  // Detached target and request generation awaiting asynchronous UUID assignment.
  property var launchIntent: null
  // Exact environment whose observed focus may dismiss this opening.
  property string awaitedReturnId: ''
  // Changing future launch checkout invalidates old dismissal intent.
  readonly property string selectedCheckoutId: selectedProject ? selectedProject.lastCheckoutId : ''
  onSelectedCheckoutIdChanged: clearDismissalIntent()
  // Forget only local visibility intent, preserving all accepted or unknown work.
  function clearDismissalIntent() {
    inspectionLaunchIntent = null
    awaitedLaunchId = ''
    launchIntent = null
    awaitedReturnId = ''
  }
  // A UUID may arrive after submit returns; bind only this request generation and target.
  function bindLaunchIdentity() {
    var intent = launchIntent, target = projectClientObject.environmentTarget
    if (!intent || projectClientObject.generation !== intent.generation || !target || projectClientObject.submissionMethod !== 'startEnvironment')
      return
    if (['projectId', 'checkoutId', 'profileId', 'profileRevision'].every(function (key) {
      return target[key] === intent.target[key]
    }))
      awaitedLaunchId = projectClientObject.activationId
  }
  // Start the exact displayed profile on the currently selected checkout.
  function startProfile(profileId, profileRevision, another) {
    if (inert || !opened || !selectedProject || projectClientObject.submitting || inspectionLaunchIntent)
      return false
    var profile = (selectedProject.profiles || []).find(function (p) {
      return p.id === profileId && p.revision === profileRevision
    })
    if (!profile)
      return false
    var target = {
      projectId: projectId,
      checkoutId: selectedCheckoutId,
      profileId: profileId,
      profileRevision: profileRevision
    }
    clearDismissalIntent()
    var saved = (projectControllerObject.state.projects || []).find(function (project) {
      return project.id === root.projectId
    })
    if (inspectionCheckoutId && saved && saved.lastCheckoutId !== target.checkoutId) {
      if (projectControllerObject.pending || projectControllerObject.reading)
        return false
      inspectionLaunchIntent = Object.assign({}, target, {
        another: another === true
      })
      if (!projectControllerObject.request('select-checkout', {
        projectId: target.projectId,
        checkoutId: target.checkoutId
      })) {
        inspectionLaunchIntent = null
        return false
      }
      return true
    }
    launchIntent = {
      target: target,
      generation: null
    }
    var accepted = another ? projectClientObject.startAnotherEnvironment(target) : projectClientObject.startEnvironment(target)
    if (!accepted)
      clearDismissalIntent()
    else
      bindLaunchIdentity()
    return accepted
  }
  // Dismissal intent clears before stopping a known-unaccepted local retry.
  function cancelPreparation() {
    clearDismissalIntent()
    return projectClientObject.cancelPreparation()
  }
  // Return is focus-only and closes only on the matching observed signal.
  function returnEnvironment(target) {
    if (inert || !opened || !target || target.projectId !== projectId)
      return false
    clearDismissalIntent()
    awaitedReturnId = target.environmentId
    if (!projectClientObject.returnEnvironment(target)) {
      clearDismissalIntent()
      return false
    }
    return true
  }
  Connections {
    target: projectClientObject
    function onEnvironmentRequestStarted(requestGeneration, method, target) {
      var intent = root.launchIntent
      if (!intent || intent.generation !== null || method !== 'startEnvironment' || !root.opened)
        return
      if (['projectId', 'checkoutId', 'profileId', 'profileRevision'].every(function (key) {
        return target[key] === intent.target[key]
      })) {
        root.launchIntent = {
          target: intent.target,
          generation: requestGeneration
        }
        root.bindLaunchIdentity()
      }
    }
    function onActivationIdChanged() {
      root.bindLaunchIdentity()
    }
    function onEnvironmentTargetChanged() {
      root.bindLaunchIdentity()
    }
    function onSubmissionAccepted(operationId, environmentId) {
      if (root.opened && root.launchIntent && root.awaitedLaunchId && root.awaitedLaunchId === projectClientObject.activationId && operationId === projectClientObject.operationId && environmentId === projectClientObject.environmentId)
        root.close()
    }
    function onReturnObserved(environmentId) {
      if (root.opened && root.awaitedReturnId === environmentId)
        root.close()
    }
  }
  ProjectGitClient {
    id: gitClientObject
    active: root.opened
    captureActive: root.inert
    projectId: root.selectedProject ? root.selectedProject.id : ''
    checkoutId: root.selectedProject && (root.selectedProject.checkouts || []).some(function (checkout) {
      return checkout.id === root.selectedProject.lastCheckoutId
    }) ? root.selectedProject.lastCheckoutId : ''
  }
  ProjectGitCommands {
    id: gitCommands
    captureActive: root.inert
  }
  // Reads of how task checkouts differ from their base, and the Open diff launch.
  property alias reviewClient: reviewClientObject
  ProjectReviewClient {
    id: reviewClientObject
    active: root.opened
    timed: root.opened && !!root.view && root.view.section === 'overview'
    captureActive: root.inert
    projectId: gitClientObject.projectId
    checkoutId: gitClientObject.checkoutId
    tasks: (activityClientObject.snapshot || {}).tasks || []
    projects: (projectControllerObject.state || {}).projects || []
    commands: gitCommands
  }
  // One action observer shared by Overview and full Actions, including receipts.
  property alias actionClient: actionClientObject
  ProjectActionsClient {
    id: actionClientObject
    captureActive: root.inert
    projectId: gitClientObject.projectId
    checkoutId: gitClientObject.checkoutId
    summaryObservationActive: root.opened && !!root.view && root.view.section === 'overview' && root.view.activityVisible && !root.inert
    observationActive: root.opened && !!root.view && ['overview', 'actions'].indexOf(root.view.section) >= 0 && !root.inert
  }
  // Snapshot polling is read-only; native protected-run observation stays in the client.
  Timer {
    interval: 5000
    running: actionClientObject.observationActive
    triggeredOnStart: true
    repeat: true
    onTriggered: root.refreshActions()
  }
  // A selection switch clears the snapshot; read the new one once both identities settle.
  Connections {
    target: actionClientObject
    function onProjectIdChanged() {
      root.refreshActionsSoon()
    }
    function onCheckoutIdChanged() {
      root.refreshActionsSoon()
    }
  }
  // Coalesces the project and checkout changes of one switch into one read.
  function refreshActionsSoon() {
    if (actionClientObject.observationActive)
      Qt.callLater(root.refreshActions)
  }
  // Explicit snapshot/capability refresh never starts a saved command.
  function refreshActions() {
    if (inert || !opened || !actionClientObject.projectId)
      return
    actionClientObject.refresh()
    actionClientObject.checkAvailability()
    actionClientObject.observeSummary()
  }
  ProjectRegistryClient {
    id: projectControllerObject
    captureActive: root.inert
  }
  ProjectClient {
    id: projectClientObject
    captureActive: root.inert
  }
  ProjectDiscoveryController {
    id: discoveryClientObject
    captureActive: root.inert
  }
  Connections {
    target: projectControllerObject
    function onStateChanged() {
      root.restoreNavigation()
      root.applyInspection()
    }
    function onReadingChanged() {
      if (!projectControllerObject.reading) {
        root.restoreNavigation()
        root.applyInspection()
        root.flushNavigation()
      }
    }
    function onPendingChanged() {
      if (!projectControllerObject.pending) {
        if (projectControllerObject.error)
          root.inspectionLaunchIntent = null
        root.navigationSaving = false
        root.applyInspection()
        root.flushNavigation()
      }
    }
    function onRootReady(rootId) {
      discoveryClientObject.start(rootId)
    }
    function onMutationCompleted(action, args, state) {
      if (action === 'select-checkout' && root.projectId === args.projectId) {
        let intent = root.inspectionLaunchIntent
        root.inspectionLaunchIntent = null
        root.inspectionCheckoutId = ''
        if (intent && root.opened && !root.inert && intent.projectId === args.projectId && intent.checkoutId === args.checkoutId && root.selectedCheckoutId === intent.checkoutId)
          root.startProfile(intent.profileId, intent.profileRevision, intent.another)
      }
      if (action === 'register') {
        let added = state.projects.filter(function (p) {
          return p.checkouts.some(function (c) {
            return args.paths.indexOf(c.path) >= 0
          })
        })[0]
        if (added)
          root.projectId = added.id
        discoveryClientObject.candidates = discoveryClientObject.candidates.filter(function (c) {
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
        discoveryClientObject.candidates = discoveryClientObject.candidates.filter(function (c) {
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
  property alias activityClient: activityClientObject
  Activity.ActivityClient {
    id: activityClientObject
    captureActive: root.inert
  }
  Timer {
    interval: 5000
    running: root.opened && !!root.view && root.view.activityVisible && !root.inert
    repeat: true
    triggeredOnStart: true
    onTriggered: activityClientObject.refresh()
  }
  // Capture shared observations once, independently of a full Actions view.
  function actionSnapshot() {
    var saved = {};
    ['snapshot', 'snapshotProjectId', 'currentRun', 'runId', 'requestId', 'submissionUncertain', 'submissionTarget', 'availability', 'available', 'error', 'output', 'truncated', 'summaryError'].forEach(function (key) {
      saved[key] = actionClientObject[key]
    })
    return saved
  }
  // Restore only passive state while capture guards all external boundaries.
  function restoreActions(saved) {
    var defaults = {
      snapshot: {
        revision: 0,
        definitions: [],
        runs: [],
        requests: []
      },
      snapshotProjectId: '',
      currentRun: null,
      runId: '',
      requestId: '',
      submissionUncertain: false,
      submissionTarget: null,
      availability: {},
      available: false,
      error: null,
      output: '',
      truncated: false,
      summaryError: null
    }
    Object.keys(defaults).forEach(function (key) {
      actionClientObject[key] = saved && saved[key] !== undefined ? saved[key] : defaults[key]
    })
  }
  // Scoped inert capture state, with drafts restored to their exact identities.
  property var captureSaved: null
  // Serialize local presentation and observations without backend reads.
  function captureSnapshot() {
    return JSON.stringify({
      opened: opened,
      mode: mode,
      section: section,
      projectId: projectId,
      inspectionCheckoutId: inspectionCheckoutId,
      inspectionError: inspectionError,
      projects: {
        state: projectControllerObject.state,
        tools: projectControllerObject.tools,
        error: projectControllerObject.error,
        errorObject: projectControllerObject.errorObject,
        extraErrorObject: projectControllerObject.extraErrorObject,
        failure: discoveryClientObject.failure,
        candidates: discoveryClientObject.candidates,
        partial: discoveryClientObject.partial,
        errors: discoveryClientObject.errors,
        snapshot: projectClientObject.snapshot,
        available: projectClientObject.available,
        clientError: projectClientObject.error,
        requestError: projectClientObject.requestError,
        acceptanceUnknown: projectClientObject.acceptanceUnknown
      },
      actions: actionSnapshot(),
      gitCache: gitClientObject.cache,
      reviews: reviewClientObject.reviews,
      activity: {
        snapshot: activityClientObject.snapshot,
        available: activityClientObject.available,
        error: activityClientObject.error
      },
      ui: view ? view.captureSnapshot() : null
    })
  }
  // Validate and enter an inert transaction before changing any observation.
  function captureBegin(payloadJson) {
    if (inspectionDestination || actionClientObject.pending || activityClientObject.pending || projectControllerObject.pending || projectControllerObject.reading || projectClientObject.pending || projectClientObject.preparing || discoveryClientObject.pending || captureSaved || (view && view.captureBusy()))
      return 'busy'
    var payload
    try {
      payload = JSON.parse(payloadJson)
    } catch (e) {
      return 'invalid'
    }
    if (!payload || payload.snapshot !== captureSnapshot() || !payload.fixture || !payload.fixture.projectsState || !Array.isArray(payload.fixture.projectsState.roots) || !Array.isArray(payload.fixture.projectsState.ignored) || !Array.isArray(payload.fixture.projectsState.projects) || (payload.section !== undefined && payload.section !== 'projects') || (payload.mode !== undefined && payload.mode !== '' && payload.mode !== 'switcher') || (payload.projectId !== undefined && payload.projectId !== '' && Logic.normalizeProjectId(payload.projectId) !== payload.projectId) || (payload.fixture.projectCandidates !== undefined && !Array.isArray(payload.fixture.projectCandidates)))
      return 'invalid'
    captureSaved = {
      json: payload.snapshot,
      focus: view ? view.captureFocus() : null
    }
    inspectionCheckoutId = ''
    inspectionError = ''
    // The compact quick switcher is presentation only: the same inert fixture, another layout.
    mode = payload.mode === 'switcher' ? 'switcher' : ''
    projectId = Logic.normalizeProjectId(payload.projectId)
    var f = payload.fixture
    restoreActions(f.projectActions || {})
    gitClientObject.cache = f.projectGitCache || {}
    reviewClientObject.reviews = f.projectReviews || {}
    activityClientObject.snapshot = f.activitySnapshot || {
      tasks: [],
      operations: []
    }
    activityClientObject.available = false
    activityClientObject.error = null
    projectControllerObject.state = f.projectsState
    projectControllerObject.tools = f.projectTools || {
      defaults: {},
      editors: [],
      terminals: []
    }
    projectControllerObject.error = f.projectError || ''
    projectControllerObject.errorObject = null
    projectControllerObject.extraErrorObject = null
    discoveryClientObject.candidates = f.projectCandidates || []
    discoveryClientObject.partial = f.projectPartial === true
    discoveryClientObject.errors = f.projectErrors || []
    discoveryClientObject.failure = null
    projectClientObject.snapshot = f.projectSnapshot || {}
    projectClientObject.available = f.projectAvailable === true
    projectClientObject.error = ''
    projectClientObject.requestError = null
    projectClientObject.acceptanceUnknown = f.projectAcceptanceUnknown === true
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
    gitClientObject.cache = saved.gitCache || {}
    reviewClientObject.reviews = saved.reviews || {}
    activityClientObject.snapshot = saved.activity.snapshot
    activityClientObject.available = saved.activity.available
    activityClientObject.error = saved.activity.error
    projectControllerObject.state = p.state
    projectControllerObject.tools = p.tools
    projectControllerObject.error = p.error
    projectControllerObject.errorObject = p.errorObject || null
    projectControllerObject.extraErrorObject = p.extraErrorObject || null
    discoveryClientObject.candidates = p.candidates
    discoveryClientObject.partial = p.partial
    discoveryClientObject.errors = p.errors
    discoveryClientObject.failure = p.failure || null
    projectClientObject.snapshot = p.snapshot
    projectClientObject.available = p.available
    projectClientObject.error = p.clientError
    projectClientObject.requestError = p.requestError
    projectClientObject.acceptanceUnknown = p.acceptanceUnknown === true
    projectId = saved.projectId
    inspectionCheckoutId = saved.inspectionCheckoutId || ''
    inspectionError = saved.inspectionError || ''
    opened = saved.opened
    mode = saved.mode || ''
    if (view && saved.ui)
      view.captureRestore(saved.ui)
    restoreActions(saved.actions || {})
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
  function applyInspection() {
    if (inert || !opened || !inspectionDestination || !view || projectControllerObject.reading || projectControllerObject.pending)
      return
    var target = inspectionDestination
    inspectionDestination = null
    var project = (projectControllerObject.state.projects || []).find(function (row) {
      return row.id === target.projectId
    })
    if (!project || !(project.checkouts || []).some(function (checkout) {
      return checkout.id === target.checkoutId
    })) {
      inspectionError = 'The requested checkout is no longer registered. Choose a project or add its folder again.'
      return
    }
    view.inspectCheckout(target.projectId, target.checkoutId)
  }
  // Accept a typed destination and refresh observations without launching tools.
  function open(payloadJson) {
    clearDismissalIntent()
    if (inert)
      return 'busy'
    var payload = {}
    try {
      payload = JSON.parse(payloadJson || '{}')
    } catch (e) {}
    var nextId = payload && payload.projectId !== undefined ? Logic.normalizeProjectId(payload.projectId) : projectId
    inspectionError = ''
    inspectionDestination = null
    var switcher = !!payload && payload.mode === 'switcher'
    if (switcher && view && view.switcherBlocked) {
      // An open window keeps its draft; a hidden one comes back as the full layout.
      if (opened)
        return 'busy'
      switcher = false
    }
    if (switcher) {
      mode = 'switcher'
      restoreNavigationPending = false
      opened = true
      projectControllerObject.refresh()
      projectClientObject.refresh()
      if (view)
        view.focusKeys()
      return 'ok'
    }
    if (payload && payload.checkoutId !== undefined) {
      if (!nextId || typeof payload.checkoutId !== 'string' || !payload.checkoutId || /[\x00-\x1f\x7f]/.test(payload.checkoutId))
        return 'invalid'
      if (view && view.navigationBlocked)
        return 'busy'
      restoreNavigationPending = false
      inspectionDestination = {
        projectId: nextId,
        checkoutId: payload.checkoutId
      }
      mode = ''
      opened = true
      projectControllerObject.refresh()
      applyInspection()
      projectClientObject.refresh()
      if (view)
        view.focusKeys()
      return 'ok'
    }
    if (view && nextId !== projectId && view.navigationBlocked)
      return 'busy'
    if (view && nextId !== projectId && view.hasUnsavedDraft) {
      mode = ''
      opened = true
      view.navigate(nextId)
      return 'ok'
    }
    mode = ''
    restoreNavigationPending = !payload || payload.projectId === undefined
    projectId = nextId
    opened = true
    projectControllerObject.refresh()
    restoreNavigation()
    projectClientObject.refresh()
    if (view)
      view.focusKeys()
    return 'ok'
  }
  // Hide presentation while retaining drafts and accepted service operations.
  function close() {
    inspectionDestination = null
    clearDismissalIntent()
    opened = false
    // Without a window there is no fade-out to protect.
    if (!view)
      mode = ''
  }
  // The window has finished closing and is gone: the next open starts from the full layout.
  function closeFinished() {
    if (!opened)
      mode = ''
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
