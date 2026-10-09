// Local runtime source/activation controller. The owning menu supplies existing
// app/menu watchers and handles their activation; this owns only live refresh.
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
      actionRecords: sources.actionController ? sources.actionController.records : []
    }
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
    var record = Search.resolveTarget(Targets.sourceRecords(data), key)
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
