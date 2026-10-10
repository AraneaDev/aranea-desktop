// Exact-project agent tasks reuse the existing activity service and detail controls.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.agents" as Agents
import "../araneadev.agents/AgentTasksLogic.js" as Logic
import "../araneadev.shared" as Aranea

ColumnLayout {
  id: view
  // Exact selected registration used to filter task associations.
  property var project: null
  // Read-only registrations used for exact project and checkout labels.
  property var registry: ({
      projects: []
    })
  // Persistent activity-service observer and fixed-action submission boundary.
  property var client: null
  // Inert captures refuse all activity reads and submissions.
  property bool displayOnly: false
  // Available viewport height for the reused task list and details.
  property real maxHeight: Style.space(600)
  // Only exact registered checkout associations belong to this project.
  readonly property var projectTasks: (client ? client.snapshot.tasks || [] : []).filter(function (task) {
    var a = task.association || {}
    return !!project && a.status === 'registered' && a.projectId === project.id && (project.checkouts || []).some(function (co) {
      return co.id === a.checkoutId && co.path === a.cwd
    })
  })
  // Stable task/action context remains available after transport uncertainty.
  property string actionTaskId: ''
  // Fixed enum only; provider text can never become action input.
  property string actionKind: ''
  // Accepted owner-loss records outlive transient client transport errors.
  property var uncertainOperations: []
  // Persist exact accepted identity when an owner/lifetime read becomes uncertain.
  function retainOperationError() {
    if (!client || displayOnly)
      return
    var error = client.error
    if (!error || ['OWNER_UNAVAILABLE', 'OPERATION_LOST'].indexOf(error.code) < 0)
      return
    var op = client.currentOperation
    if (!op && actionTaskId && actionKind === 'reopen')
      op = {
        id: client.operationId,
        ownerId: client.ownerId,
        taskId: actionTaskId,
        action: actionKind,
        state: 'completed',
        outcome: 'partial'
      }
    if (!op || op.action !== 'reopen')
      return
    var copy = Object.assign({}, op, {
      ownerUnconfirmed: true,
      ownerLossError: Object.assign({}, error)
    })
    uncertainOperations = uncertainOperations.filter(function (record) {
      return record.id !== copy.id || record.ownerId !== copy.ownerId || record.taskId !== copy.taskId
    }).concat([copy])
  }
  // Only successful observation of this exact owner/operation clears its uncertainty.
  function operationObserved(op) {
    uncertainOperations = uncertainOperations.filter(function (record) {
      return record.id !== op.id || record.ownerId !== op.ownerId || record.taskId !== op.taskId
    })
  }
  Connections {
    target: view.client
    ignoreUnknownSignals: true
    function onErrorChanged() {
      view.retainOperationError()
    }
    function onOperationChanged(op) {
      view.operationObserved(op)
    }
  }
  // First-read failure retains known acceptance even without a populated operation.
  readonly property var taskOperation: client ? client.currentOperation || (actionTaskId && actionKind === 'reopen' && client.error ? ({
        id: client.operationId,
        ownerId: client.ownerId,
        taskId: actionTaskId,
        action: actionKind,
        state: 'completed',
        outcome: 'partial',
        submissionUnconfirmed: true,
        error: client.error
      }) : null) : null
  // Serialize task list, nested details and exact acceptance protection without IO.
  function captureSnapshot() {
    return {
      tasks: tasks.captureSnapshot(),
      actionTaskId: actionTaskId,
      actionKind: actionKind,
      uncertainOperations: uncertainOperations
    }
  }
  // Restore nested cursor and scroll state after restoring task observations.
  function captureRestore(saved) {
    actionTaskId = saved.actionTaskId || ''
    actionKind = saved.actionKind || ''
    uncertainOperations = saved.uncertainOperations || []
    tasks.captureRestore(saved.tasks || {})
  }
  // Give task navigation a real Tab target in the standalone window.
  function focusTasks() {
    tasks.forceActiveFocus(Qt.TabFocusReason)
  }
  // Reuse the reveal-first task/detail keyboard model and local Escape behavior.
  function handleKey(event) {
    if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
      tasks.navigate(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
      tasks.navigate(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      tasks.navigate(0)
      event.accepted = true
    } else if (event.key === Qt.Key_Escape && tasks.selectedId) {
      tasks.back()
      event.accepted = true
    } else if (event.key === Qt.Key_R && !displayOnly && client && !client.captureActive) {
      client.refresh()
      event.accepted = true
    }
  }
  // Submit only an allowed action for a current exact-project task row.
  function submit(kind, id) {
    if (displayOnly || !client || client.captureActive || client.pending)
      return
    var row = tasks.taskRows.filter(function (r) {
      return r.key === id
    })[0]
    if (!row)
      return
    var retained = tasks.operationFor(id), outcome = Logic.operationView(retained, client.error, client.pending)
    if (kind === 'reconnect' && retained && outcome.canReconnect) {
      client.reconnect(retained.id)
      return
    }
    if (kind === 'reobserve' && retained && outcome.canReobserve && client.operationId === retained.id) {
      client.reobserve()
      return
    }
    if (outcome.protected)
      return
    actionTaskId = id
    actionKind = kind
    if (kind === 'dismiss' && row.canDismiss)
      client.dismiss(id)
    else if (['focus', 'reopen', 'open-checkout'].indexOf(kind) >= 0 && (kind === 'open-checkout' && row.assigned || kind === row.primary.kind || row.secondary && kind === row.secondary.kind))
      client.request({
        action: kind,
        taskId: id
      })
  }
  // Route setup to the host wizard without opening another application.
  signal setupRequested
  spacing: Style.space(8)
  Aranea.UiLabel {
    Layout.fillWidth: true
    text: 'Agent activity for ' + (view.project ? view.project.name : 'this project')
    font.bold: true
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    text: 'Only sessions reported from an exact registered checkout appear here.'
    opacity: 0.65
  }
  Aranea.ActionButton {
    text: 'Refresh activity'
    enabled: !view.displayOnly && !!view.client && !view.client.pending
    onClicked: view.client.refresh()
  }
  Agents.AgentTasks {
    id: tasks
    activeFocusOnTab: true
    Keys.onPressed: function (event) {
      view.handleKey(event)
    }
    Layout.fillWidth: true
    Layout.preferredHeight: Math.max(Style.space(160), Math.min(implicitHeight, view.maxHeight))
    maxHeight: view.maxHeight
    snapshot: ({
        tasks: view.projectTasks,
        operations: view.client ? view.client.snapshot.operations || [] : []
      })
    projectSnapshot: view.registry
    captureActive: view.displayOnly
    error: view.client ? view.client.error : null
    pending: !!view.client && view.client.pending
    operation: view.taskOperation
    uncertainOperations: view.uncertainOperations
    onAction: function (kind, id) {
      if (kind === 'setup') {
        view.setupRequested()
        return
      }
      view.submit(kind, id)
    }
  }
  Aranea.WorkflowHelp {
    Layout.fillWidth: true
    topic: 'agents'
    visible: view.projectTasks.length === 0
  }
}
