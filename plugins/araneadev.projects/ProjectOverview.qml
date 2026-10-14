// Read-only composition; the surface routes explicit effects to persistent clients.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

ColumnLayout {
  id: view
  objectName: 'projectOverview'
  // Pure selected-checkout presentation rows supplied by the surface.
  property var model: ({
      git: null,
      services: [],
      checks: [],
      agents: [],
      workspaces: []
    })
  // Selected Git read error retains its prior snapshot.
  property var gitError: null
  // Independent selected Git read progress.
  property bool gitLoading: false
  // Capture boundary refuses every external action.
  property bool displayOnly: false
  // Shared action acceptance or execution request is pending.
  property bool actionPending: false
  // Shared activity request is pending.
  property bool agentPending: false
  // Owner is unavailable or processing a workspace request.
  property bool workspacePending: false
  // Native command availability gates Run and Start.
  property bool executionAvailable: false
  // Readable shared-action transport or receipt uncertainty.
  property string actionError: ''
  // Readable activity connection uncertainty.
  property string activityError: ''
  // Shared pointer settlement gate for moving content.
  property var pointerGate: null
  // Injected presentation clock for stale-state copy.
  property real nowMs: Date.now()
  // Exact saved action revision or retained run request.
  signal actionRequested(string method, var target)
  // Fixed activity method and exact task identity.
  signal agentRequested(string method, string taskId)
  // Ordinary owner Open for the selected checkout.
  signal workspaceRequested(var target)
  // Open deeper information without executing saved commands.
  signal detailsRequested(string section, var target)
  // Explicit read-only refresh request.
  signal refreshRequested
  spacing: Style.space(20)
  ProjectGitSection {
    Layout.fillWidth: true
    git: view.model.git
    error: view.gitError
    loading: view.gitLoading
    displayOnly: view.displayOnly
    pointerGate: view.pointerGate
    nowMs: view.nowMs
    onRefreshRequested: view.refreshRequested()
  }
  ColumnLayout {
    Layout.fillWidth: true
    Aranea.UiLabel {
      Layout.fillWidth: true
      visible: !!view.actionError
      text: view.actionError
      color: Aranea.DesignTokens.urgent
    }
    ProjectActivitySummary {
      Layout.fillWidth: true
      objectName: 'overviewCommands'
      title: 'Services and checks'
      detailsLabel: 'Manage actions'
      emptyHint: 'Save a test, build or dev server to run from here.'
      rows: view.model.services.concat(view.model.checks).sort(function (a, b) {
        return Number(b.active) - Number(a.active) || Number(b.attention) - Number(a.attention)
      })
      displayOnly: view.displayOnly
      pending: view.actionPending
      executionAvailable: view.executionAvailable
      pointerGate: view.pointerGate
      onRequested: function (method, target) {
        view.actionRequested(method, target)
      }
      onDetailsRequested: function (target) {
        view.detailsRequested('actions', target)
      }
    }
  }
  ColumnLayout {
    Layout.fillWidth: true
    Aranea.UiLabel {
      Layout.fillWidth: true
      visible: !!view.activityError
      text: view.activityError
      color: Aranea.DesignTokens.urgent
    }
    ProjectActivitySummary {
      Layout.fillWidth: true
      title: 'Agents'
      detailsLabel: view.model.agents.length ? 'Agent details' : 'Set up agents'
      emptyHint: 'Start or connect an agent to see activity in this checkout.'
      rows: view.model.agents
      displayOnly: view.displayOnly
      pending: view.agentPending
      pointerGate: view.pointerGate
      onRequested: function (method, target) {
        view.agentRequested(method, target.taskId)
      }
      onDetailsRequested: function (target) {
        view.detailsRequested('agents', target)
      }
    }
  }
  ProjectActivitySummary {
    Layout.fillWidth: true
    title: 'Workspaces'
    detailsLabel: 'Workspace details'
    emptyHint: 'No observed workspace here. Open your tools from the project header.'
    rows: view.model.workspaces
    displayOnly: view.displayOnly
    pending: view.workspacePending
    pointerGate: view.pointerGate
    onRequested: function (method, target) {
      view.workspaceRequested(target)
    }
    onDetailsRequested: function (target) {
      view.detailsRequested('preferences', target)
    }
  }
}
