// Local runtime source/activation controller. The owning menu supplies existing
// app/menu watchers and handles their activation; this owns only live refresh.
import "../araneadev.projects/ProjectRecords.js" as Projects
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "DesktopSearchLogic.js" as Search
import "DesktopSearchTargets.js" as Targets
import "MenuModel.js" as MenuModel

Item {
  id: sources

  // Existing host source projections; no duplicate file or app watchers.
  property var appRows: []
  // Current merged menu items indexed by canonical menu ID.
  property var menuItems: ({})
  // Existing menu tree traversal order; defaults to item keys.
  property var itemOrder: []
  // Current results from the owning menu guard evaluator.
  property var whenResults: ({})
  // Existing pinned application identities.
  property var favoriteAppIds: []
  // Existing recent application identities, newest first.
  property var recentAppIds: []
  // Availability from the existing settings manifest watcher.
  property bool settingsAvailable: false
  // Persistent quick-action owner; null when that capability is unavailable.
  property var actionController: null
  // Read-only client for the single persistent project operation owner.
  property var projectClient: null
  // Owner feedback survives query edits and menu closing.
  property var projectFeedback: ({})
  // Owner session scopes authoritative feedback; empty transient snapshots do not reset it.
  property string projectSessionId: ""
  // Local preparation/refusal has its own identity, separate from owner generations.
  property var projectSubmission: null
  // Replaceable compositor and raw fixtures for offscreen integration tests.
  property var compositor: Hyprland
  // Optional raw window collection replacing the compositor model.
  property var fixtureWindows: null
  // Optional raw workspace collection replacing the compositor model.
  property var fixtureWorkspaces: null
  // Optional canonical focused workspace ID override.
  property var fixtureFocusedWorkspaceId: null
  // Fresh synchronous snapshot boundary; activation always reads this directly.
  property var snapshotReader: function () {
    return sources.liveSnapshot()
  }
  // Optional async refresh boundary: function(generation, complete). Activation
  // never uses its cached/coalesced results. Complete receives generation/data.
  property var refreshReader: null
  // Argument-array boundary; tests replace it with a recorder.
  property var runner: function (argv) {
    Quickshell.execDetached(argv)
    return true
  }

  // The owning menu sets this only while its search runtime is open.
  property bool active: false
  // Complete current normalized source records; ranking belongs to host.
  property var records: []
  // Availability of the live compositor, independent of static destinations.
  property bool available: false
  // Publication counter observed by host selection reconciliation.
  property int revision: 0
  // Invalidates pending completion when a newer event/read or close occurs.
  property int generation: 0
  // Last accepted normalized live records, separate from fresh activation.
  property var liveRecords: []
  // Whether the coalescing timer has a refresh scheduled.
  readonly property bool refreshPending: refreshTimer.running
  // Whether the local controller connects compositor update signals.
  readonly property bool subscribed: sources.active && sources.compositor !== null

  // Host launches this currently installed app through its existing handler.
  signal appRequested(string appId, string label)
  // Host activates this current menu item through its existing handler.
  signal commandRequested(string itemId)
  // Argument-array dispatch accepted; app/menu handlers retain their close policy.
  signal activated
  // Display a notice and keep the menu open on invalid or rejected dispatch.
  signal failed(string message)

  // Merges current static inputs without reading or subscribing to compositor.
  function staticSnapshot(): var {
    var items = sources.menuItems || ({})
    var order = sources.itemOrder.length ? sources.itemOrder : Object.keys(items)
    var visible = order.map(function (id) {
      return items[id]
    }).filter(function (item) {
      return MenuModel.isVisible(items, order, sources.whenResults, item)
    })
    return {
      appRows: sources.appRows,
      menuItems: visible,
      whenResults: sources.whenResults,
      favoriteAppIds: sources.favoriteAppIds,
      recentAppIds: sources.recentAppIds,
      settingsAvailable: sources.settingsAvailable,
      actionRecords: sources.actionController ? sources.actionController.records : [],
      projectRecords: sources.currentProjectRecords()
    }
  }

  // Rebuild canonical project/checkout records from the latest owner projection.
  function currentProjectRecords(): var {
    if (!sources.active || !sources.projectClient)
      return []
    var snapshot = sources.projectClient.snapshot || ({})
    return Projects.records({
      projects: snapshot.projects || []
    }, snapshot).map(function (record) {
      record.aliases = [record.label].concat(record.aliases)
      record.label = (record.action === "resume" ? "Resume " : "Open ") + record.label
      var project = (snapshot.projects || []).find(function (candidate) {
        return candidate.id === record.target.projectId
      })
      var binding = (snapshot.bindings || []).find(function (candidate) {
        return candidate.projectId === record.target.projectId && candidate.checkoutId === record.target.checkoutId && candidate.sessionId === snapshot.sessionId
      })
      var association = project && (project.associations || []).find(function (candidate) {
        return candidate.checkoutId === record.target.checkoutId && !candidate.separate
      })
      var workspace = binding && binding.workspaceId || association && association.workspaceId
      record.detail += workspace ? " · Workspace " + workspace : project && project.workspaceMode === "current" ? " · Current workspace" : " · Dedicated workspace"
      return record
    })
  }

  // A real session replacement invalidates prior feedback and local preparation identity.
  function syncProjectSession(): void {
    var next = sources.projectClient && sources.projectClient.snapshot.sessionId
    if (!next || next === sources.projectSessionId)
      return
    sources.projectSessionId = next
    sources.projectFeedback = ({})
    sources.projectSubmission = null
  }

  // Exact checkout keys keep independent operation generations from overwriting each other.
  function projectFeedbackKey(projectId: string, checkoutId: string): string {
    return projectId + "\n" + checkoutId
  }

  // Local progress is visible only until a newer accepted operation supersedes it.
  function feedbackForProject(projectId: string, checkoutId: string): var {
    var key = projectFeedbackKey(projectId, checkoutId)
    var authoritative = sources.projectFeedback[key]
    var local = sources.projectSubmission
    if (local && local.key === key && local.sessionId === sources.projectSessionId && (!authoritative || authoritative.generation <= local.baselineGeneration))
      return local
    return authoritative || null
  }

  // Preserve current-session highest-generation outcomes without taking launch ownership.
  function projectOperationChanged(operation: var): void {
    syncProjectSession()
    if (!operation || !operation.id || !operation.projectId || !operation.checkoutId || !sources.projectSessionId || operation.sessionId !== sources.projectSessionId || !Number.isInteger(operation.generation))
      return
    var key = projectFeedbackKey(operation.projectId, operation.checkoutId)
    var previous = sources.projectFeedback[key]
    if (previous && (previous.generation > operation.generation || previous.generation === operation.generation && (previous.operationId !== operation.id || previous.completed && operation.state !== "completed")))
      return
    var feedback = Object.assign({}, sources.projectFeedback)
    feedback[key] = {
      checkoutId: operation.checkoutId,
      sessionId: operation.sessionId,
      generation: operation.generation,
      operationId: operation.id,
      completed: operation.state === "completed",
      status: operation.state !== "completed" ? "pending" : operation.outcome || "failed",
      message: operation.error && operation.error.message ? operation.error.message : operation.state !== "completed" ? "Opening project…" : operation.outcome === "observed" ? "Project ready" : "Project launch " + (operation.outcome || "failed")
    }
    sources.projectFeedback = feedback
    var local = sources.projectSubmission
    if (local && local.key === key && (operation.generation > local.baselineGeneration || operation.id === sources.projectClient.operationId))
      sources.projectSubmission = null
    sources.publish()
  }

  // Iterates live QObject models only on an explicit active refresh/activation.
  function liveSnapshot(): var {
    if (!sources.active)
      return {
        compositorAvailable: false,
        windows: [],
        workspaces: []
      }
    var host = sources.compositor
    var windows = sources.fixtureWindows !== null ? sources.fixtureWindows : host && host.toplevels ? host.toplevels : []
    var workspaces = sources.fixtureWorkspaces !== null ? sources.fixtureWorkspaces : host && host.workspaces ? host.workspaces : []
    var focused = sources.fixtureFocusedWorkspaceId !== null ? sources.fixtureFocusedWorkspaceId : host && host.focusedWorkspace ? host.focusedWorkspace.id : null
    return {
      compositorAvailable: sources.fixtureWindows !== null || sources.fixtureWorkspaces !== null || !!(host && host.toplevels && host.workspaces),
      windows: Targets.collectionValues(windows),
      workspaces: Targets.collectionValues(workspaces),
      focusedWorkspaceId: focused
    }
  }

  // Joins an explicit raw live read with the freshest static source properties.
  function joinedSnapshot(live: var): var {
    var data = sources.staticSnapshot()
    data.compositorAvailable = !!(live && live.compositorAvailable)
    data.windows = live ? live.windows : []
    data.workspaces = live ? live.workspaces : []
    data.focusedWorkspaceId = live ? live.focusedWorkspaceId : null
    return data
  }

  // Publishes a source revision; selection and query generation belong to host.
  function publish(): void {
    sources.records = Search.normalizeRecords(Targets.sourceRecords(sources.staticSnapshot()).concat(sources.liveRecords))
    sources.revision += 1
  }

  // Activates/deactivates subscriptions and invalidates every outstanding read.
  function setActive(value: bool): void {
    sources.active = value
  }
  onActiveChanged: {
    sources.generation += 1
    refreshTimer.stop()
    if (sources.active) {
      sources.publish()
      sources.requestRefresh()
    } else {
      sources.liveRecords = []
      sources.available = false
      sources.publish()
    }
  }

  // Fixed 100ms leading-edge coalescing prevents bursts from starving refresh.
  function requestRefresh(): void {
    if (!sources.active)
      return
    sources.generation += 1
    if (!refreshTimer.running)
      refreshTimer.start()
  }

  // Starts one refresh generation, with a replaceable completion-based boundary.
  function refreshNow(): void {
    if (!sources.active)
      return
    refreshTimer.stop()
    if (sources.projectClient)
      sources.projectClient.refresh()
    var token = ++sources.generation
    try {
      if (sources.refreshReader) {
        sources.refreshReader(token, function (completed, snapshot) {
          sources.completeRefresh(completed, snapshot)
        })
      } else {
        sources.completeRefresh(token, sources.snapshotReader())
      }
    } catch (error) {
      sources.completeRefresh(token, null)
    }
  }

  // Older responses cannot restore a window removed by a newer read or close.
  function completeRefresh(token: int, snapshot: var): void {
    if (!sources.active || token !== sources.generation)
      return
    sources.available = !!(snapshot && snapshot.compositorAvailable)
    sources.liveRecords = Search.normalizeRecords(Targets.sourceRecords(sources.joinedSnapshot(snapshot))).filter(function (row) {
      return row.type === "window" || row.type === "workspace"
    })
    sources.publish()
  }

  // Resolve against a fresh raw snapshot immediately before any dispatch.
  function activate(key: string): bool {
    if (!sources.active)
      return false
    var data
    try {
      data = sources.joinedSnapshot(sources.snapshotReader())
    } catch (error) {
      data = sources.joinedSnapshot(null)
    }
    if (sources.actionController)
      data.actionRecords = sources.actionController.currentRecords()
    var selected = Search.resolveTarget(sources.records, key)
    var record = Search.resolveTarget(Targets.sourceRecords(data), key)
    if (key.indexOf("project:") === 0) {
      var projectRequest = Targets.dispatchTarget(selected, data)
      if (!projectRequest || !sources.projectClient || sources.projectClient.captureActive || sources.projectClient.pending) {
        sources.failed("Project is busy or selected checkout is no longer available")
        return false
      }
      syncProjectSession()
      var feedbackKey = projectFeedbackKey(projectRequest.payload.projectId, projectRequest.payload.checkoutId)
      var previous = sources.projectFeedback[feedbackKey]
      sources.projectSubmission = {
        key: feedbackKey,
        checkoutId: projectRequest.payload.checkoutId,
        sessionId: sources.projectSessionId,
        clientGeneration: sources.projectClient.generation + 1,
        baselineGeneration: previous ? previous.generation : -1,
        status: "pending",
        message: "Opening project…"
      }
      sources.publish()
      if (!sources.projectClient.request(projectRequest.payload)) {
        sources.projectSubmission = Object.assign({}, sources.projectSubmission, {
          status: "failed",
          message: "Project request refused"
        })
        sources.publish()
        sources.failed("Project request refused")
        return false
      }
      return true
    }
    if (record && record.type === "action") {
      if (sources.actionController.activate(record.key))
        return true
      sources.failed("Action is busy or no longer available")
      return false
    }
    var request = Targets.dispatchTarget(record, data)
    if (!request) {
      sources.failed(key.indexOf("window:") === 0 ? "Window is no longer open" : "Target is no longer available")
      return false
    }
    try {
      if (request.kind === "app")
        sources.appRequested(request.appId, request.label)
      else if (request.kind === "command")
        sources.commandRequested(request.itemId)
      else if (sources.runner(request.argv) === false) {
        sources.failed("Could not open target")
        return false
      }
    } catch (error) {
      sources.failed("Could not open target")
      return false
    }
    if (request.kind === "argv")
      sources.activated()
    return true
  }

  // Readiness refusals remain pending only until the client's bounded deadline.
  function projectClientError(): void {
    var client = sources.projectClient
    if (!client || !client.error || client.pending && client.requestError && client.requestError.code === "OWNER_NOT_READY")
      return
    var local = sources.projectSubmission
    if (!local || local.clientGeneration !== client.generation)
      return
    sources.projectSubmission = Object.assign({}, local, {
      status: "failed",
      message: client.error
    })
    sources.publish()
    sources.failed(client.error)
  }

  // Secondary details uses the public navigation boundary and never submits Open.
  function openProjectDetails(key: string): bool {
    if (!sources.active || !sources.projectClient || sources.projectClient.captureActive)
      return false
    var record = Search.resolveTarget(sources.currentProjectRecords(), key)
    if (!record) {
      sources.failed("Project is no longer available")
      return false
    }
    try {
      if (sources.runner(["aranea", "projects", "details", record.target.projectId]) === false) {
        sources.failed("Could not open project details")
        return false
      }
    } catch (error) {
      sources.failed("Could not open project details")
      return false
    }
    sources.activated()
    return true
  }

  onProjectClientChanged: {
    syncProjectSession()
    publish()
  }
  onAppRowsChanged: publish()
  onMenuItemsChanged: publish()
  onItemOrderChanged: publish()
  onWhenResultsChanged: publish()
  onFavoriteAppIdsChanged: publish()
  onRecentAppIdsChanged: publish()
  onSettingsAvailableChanged: publish()
  onActionControllerChanged: publish()
  onFixtureWindowsChanged: requestRefresh()
  onFixtureWorkspacesChanged: requestRefresh()
  onFixtureFocusedWorkspaceIdChanged: requestRefresh()
  onCompositorChanged: requestRefresh()
  Component.onCompleted: publish()

  Timer {
    id: refreshTimer
    interval: 100
    repeat: false
    onTriggered: sources.refreshNow()
  }
  Connections {
    target: sources.projectClient
    function onSnapshotChanged() {
      sources.syncProjectSession()
      var operations = sources.projectClient.snapshot.operations || []
      operations.forEach(function (operation) {
        sources.projectOperationChanged(operation)
      })
      sources.publish()
    }
    function onOperationChanged(operation) {
      sources.projectOperationChanged(operation)
    }
    function onErrorChanged() {
      sources.projectClientError()
    }
    function onPendingChanged() {
      sources.projectClientError()
    }
  }
  Connections {
    target: sources.actionController
    function onRevisionChanged() {
      sources.publish()
    }
  }
  Connections {
    target: sources.subscribed ? sources.compositor : null
    function onRawEvent(event) {
      sources.requestRefresh()
    }
    function onFocusedWorkspaceChanged() {
      sources.requestRefresh()
    }
  }
}
