// Read-only composition; the surface routes explicit effects to persistent clients.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea
import "ProjectOverview.js" as Overview
import "ProjectActionSuggestions.js" as Suggestions
import "ProjectProblems.js" as Problems

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
  // Read-only summary links expose work and attention before the detailed sections.
  readonly property var activitySummary: Overview.activitySummary(model, {
    actions: actionObservationAvailable,
    agents: agentObservationAvailable
  })
  // Retained records do not imply that either observer is still connected.
  property bool actionObservationAvailable: true
  // Current agent-owner transport availability is independent of cached task freshness.
  property bool agentObservationAvailable: true
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
  // Plain note about shared actions that is not a failure.
  property string actionError: ''
  // Shared-action failure or uncertain start as {code, message, recovery}, or null.
  property var actionProblem: null
  // Check again and Refresh read the shared action state; they never run anything.
  signal actionRefreshRequested
  // Readable activity connection uncertainty.
  property string activityError: ''
  // Shared pointer settlement gate for moving content.
  property var pointerGate: null
  // Injected presentation clock for stale-state copy.
  property real nowMs: Date.now()
  // Optional diagnostics always retain an exact environment target.
  property string inspectedEnvironmentId: ''
  // Resolve diagnostics again from the retained exact environment row.
  readonly property var inspectedEnvironment: (model.workspaces || []).find(function (row) {
    return row.target.environmentId === view.inspectedEnvironmentId
  }) || null
  // Up to three detected commands, offered only while the project has no saved actions.
  property var suggestions: []
  // Save one detected command by its stable key; never runs it.
  signal suggestionAddRequested(string key)
  // Exact saved action revision or retained run request.
  signal actionRequested(string method, var target)
  // Fixed activity method and exact task identity.
  signal agentRequested(string method, string taskId)
  // Ordinary owner Open for the selected checkout.
  signal workspaceRequested(string method, var target)
  // Open deeper information without executing saved commands.
  signal detailsRequested(string section, var target)
  // Running Git command for the selected checkout: '', 'fetch' or 'pull'.
  property string gitCommandPending: ''
  // Last Git command failure for the selected checkout, or null.
  property var gitCommandError: null
  // Which Git command failed: 'fetch' or 'pull'.
  property string gitCommandOperation: ''
  // Any Git command is running anywhere; new ones are refused meanwhile.
  property bool gitCommandBusy: false
  // Explicit read-only refresh request.
  signal refreshRequested
  // Explicit network fetch request.
  signal fetchRequested
  // Explicit fast-forward pull request.
  signal pullRequested
  spacing: Style.space(20)
  ColumnLayout {
    Layout.fillWidth: true
    visible: view.activitySummary.length > 0
    spacing: Style.space(8)
    Aranea.UiLabel {
      Layout.fillWidth: true
      text: 'Activity in this checkout'
      font.bold: true
    }
    Flow {
      Layout.fillWidth: true
      spacing: Style.space(6)
      Repeater {
        model: view.activitySummary
        Aranea.ActionButton {
          required property var modelData
          objectName: 'activitySummary:' + modelData.section
          text: modelData.label
          width: Math.min(implicitWidth, parent.width)
          tooltipText: modelData.label
          variant: 'quiet'
          labelColor: modelData.attention ? Aranea.DesignTokens.urgent : Aranea.DesignTokens.foreground
          enabled: !view.displayOnly
          pointerGate: view.pointerGate
          onClicked: view.detailsRequested(modelData.section, {})
        }
      }
    }
  }
  ProjectGitSection {
    Layout.fillWidth: true
    git: view.model.git
    error: view.gitError
    loading: view.gitLoading
    displayOnly: view.displayOnly
    pointerGate: view.pointerGate
    nowMs: view.nowMs
    commandPending: view.gitCommandPending
    commandError: view.gitCommandError
    commandOperation: view.gitCommandOperation
    commandBusy: view.gitCommandBusy
    onRefreshRequested: view.refreshRequested()
    onFetchRequested: view.fetchRequested()
    onPullRequested: view.pullRequested()
  }
  ColumnLayout {
    Layout.fillWidth: true
    ProjectProblem {
      objectName: 'overviewActionProblem'
      Layout.fillWidth: true
      displayOnly: view.displayOnly
      pointerGate: view.pointerGate
      problem: view.actionProblem ? Problems.problem(view.actionProblem, {
        surface: 'overview',
        actions: ['checkAgain', 'refresh']
      }) : null
      onActionRequested: function () {
        if (!view.displayOnly)
          view.actionRefreshRequested()
      }
    }
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
      emptyHint: view.suggestions.length ? '' : 'Save a test, build or dev server to run from here.'
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
    ColumnLayout {
      Layout.fillWidth: true
      visible: view.suggestions.length > 0
      spacing: Style.space(6)
      Aranea.UiLabel {
        Layout.fillWidth: true
        text: 'Found in this repo'
        opacity: 0.8
      }
      Repeater {
        model: view.suggestions
        RowLayout {
          id: pick
          required property var modelData
          Layout.fillWidth: true
          Aranea.UiLabel {
            Layout.fillWidth: true
            text: pick.modelData.definition.name + ' · ' + Suggestions.sourceLine(pick.modelData)
            elide: Text.ElideRight
          }
          Aranea.ActionButton {
            objectName: 'overviewSuggestionAdd:' + pick.modelData.key
            text: 'Add'
            enabled: !view.displayOnly && !view.actionPending
            pointerGate: view.pointerGate
            onClicked: view.suggestionAddRequested(pick.modelData.key)
          }
        }
      }
      Aranea.ActionButton {
        objectName: 'overviewSuggestionsAll'
        text: 'See all in Actions'
        variant: 'quiet'
        pointerGate: view.pointerGate
        onClicked: view.detailsRequested('actions', {})
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
    id: workspaceSummary
    Layout.fillWidth: true
    objectName: 'overviewWorkspaces'
    title: 'Workspaces'
    detailsLabel: 'Workspace details'
    emptyHint: 'Start working to create a workspace for your tools.'
    rows: view.model.workspaces
    displayOnly: view.displayOnly
    pending: view.workspacePending
    pointerGate: view.pointerGate
    onRequested: function (method, target) {
      view.workspaceRequested(method, target)
    }
    onDetailsRequested: function (target) {
      if (target.environmentId)
        view.inspectedEnvironmentId = target.environmentId
      else
        workspaceSummary.expanded = !workspaceSummary.expanded
    }
  }
  ColumnLayout {
    objectName: 'environmentDetails'
    Layout.fillWidth: true
    visible: !!view.inspectedEnvironment
    Aranea.UiLabel {
      Layout.fillWidth: true
      text: view.inspectedEnvironment ? view.inspectedEnvironment.title : ''
      font.bold: true
    }
    Aranea.UiLabel {
      Layout.fillWidth: true
      text: view.inspectedEnvironment ? view.inspectedEnvironment.fullDetail || '' : ''
    }
    Aranea.UiLabel {
      Layout.fillWidth: true
      text: 'Tools may still be open. Check looks for existing tools; New window opens another.'
      opacity: 0.65
    }
    Aranea.ActionButton {
      text: 'Hide details'
      variant: 'quiet'
      pointerGate: view.pointerGate
      onClicked: view.inspectedEnvironmentId = ''
    }
  }
}
