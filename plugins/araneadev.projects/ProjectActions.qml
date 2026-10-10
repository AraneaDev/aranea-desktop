// Configured actions and exact retained runs live inside the existing project details.
pragma ComponentBehavior: Bound
// Host font tokens are runtime QObject properties.
// qmllint disable missing-property
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea
import "../araneadev.projects" as Projects
import "../araneadev.projects/ProjectActionRecords.js" as Records

ColumnLayout {
  id: actions
  objectName: 'projectActions'
  // Exact registry selection, including the persisted selected checkout ID.
  property var project: null
  // Existing workspace focus authority only.
  property var projectClient: null
  // Capture is bound before selection reads, polling and all client effects.
  property bool displayOnly: false
  // Offline action help never reads or changes the action store.
  property bool helpExpanded: false
  // Shared pointer settling boundary.
  property var pointerGate: null
  // Existing selected project page controls the observation lifetime.
  property bool active: visible
  // Stable presentation selection, never an automatic execution request.
  property string selectedActionId: ''
  // Displayed definition revision/checkout must be revealed after any change.
  property string selectedIdentity: ''
  // Exact pointer identity remembered before press, retained through replacement.
  property string pressedIdentity: ''
  // History inspection also keeps the exact pressed ID across refreshed rows.
  property string pressedRunIdentity: ''
  // Inert editor visibility; drafts survive rejected saves.
  property bool editing: false
  // Distinguish a configuration completion from unrelated run/read callbacks.
  property bool saving: false
  // Conflicts retain drafts and require fresh explicit review before an overwrite.
  property bool editConflict: false
  // Only an explicitly requested subsequent snapshot enables deliberate retry.
  property bool conflictRefreshed: false
  // Tracks the conflict snapshot read independently of availability callbacks.
  property bool conflictRefreshPending: false
  // Frozen revision explicitly reviewed by the user, never a live overwrite target.
  property int conflictRevision: 0
  // Project identity of this local draft; selection cannot transfer a Save.
  property string draftProjectId: ''
  // Latest same-ID definition may be absent if another writer removed it.
  readonly property var conflictDefinition: definitions.filter(function (d) {
    return d.id === editor.draft.id
  })[0] || null
  // Production client transport is replaceable by isolated fixtures.
  property alias client: client
  // Presentation-only editor contract used by capture and behavior tests.
  property alias editor: editor
  // Exact lookup refuses missing selected checkout instead of falling back.
  readonly property var checkout: project ? (project.checkouts || []).filter(function (c) {
    return c.id === project.lastCheckoutId
  })[0] || null : null
  // Backend projections preserve all opaque IDs and approved revisions.
  readonly property var definitions: Records.definitions(client.snapshot, project ? project.id : '')
  // Runs are scoped to exactly the selected checkout.
  readonly property var runs: checkout ? Records.runs(client.snapshot, project.id, checkout.id) : []
  // Current selected saved definition, separate from accepted immutable runs.
  readonly property var selectedAction: definitions.filter(function (d) {
    return d.id === selectedActionId
  })[0] || null
  // Live native execution availability is separate from editable configuration.
  readonly property bool executionAvailable: client.availability.execution === true
  // Capture admission must refuse an in-flight mutation or accepted submission.
  readonly property bool pending: client.pending
  Projects.ProjectActionsClient {
    id: client
    captureActive: actions.displayOnly
    projectId: actions.project ? actions.project.id : ''
    checkoutId: actions.checkout ? actions.checkout.id : ''
    observationActive: actions.active && actions.visible && !actions.displayOnly
    onSnapshotChanged: if (actions.conflictRefreshPending) {
      actions.conflictRefreshPending = false
      actions.conflictRefreshed = true
      actions.conflictRevision = snapshot.revision
    } else if (actions.conflictRefreshed && snapshot.revision !== actions.conflictRevision) {
      actions.conflictRefreshed = false
    }
    onRequestFinished: function (response) {
      if (actions.saving) {
        actions.saving = false
        if (response && response.ok) {
          actions.editing = false
          actions.editConflict = false
        } else if (response && response.error && response.error.code === 'ACTION_CONFLICT') {
          actions.editConflict = true
          actions.conflictRefreshed = false
        }
      }
    }
  }
  // Identity gates include both selection and the exact displayed definition revision.
  function actionIdentity(id: string, revision: int): string {
    return [project ? project.id : '', checkout ? checkout.id : '', id, revision].join('|')
  }
  // Only the freshly displayed same definition can authorize an action.
  function findAction(id: string, revision: int): var {
    return definitions.filter(function (d) {
      return d.id === id && d.revision === revision
    })[0] || null
  }
  // Selecting a row only reveals its command; it never invokes a backend.
  function selectAction(id: string, revision: int): void {
    if (!findAction(id, revision))
      return
    selectedActionId = id
    selectedIdentity = actionIdentity(id, revision)
  }
  // First Enter after a selection/revision/checkout change reveals only.
  function activateAction(id: string, revision: int): void {
    activateControl('start', id, revision)
  }
  // Definition operations share the same reveal-first keyboard identity guard.
  function activateControl(method: string, id: string, revision: int): void {
    if (selectedActionId !== id || selectedIdentity !== actionIdentity(id, revision)) {
      selectAction(id, revision)
      return
    }
    performControl(method, id, revision)
  }
  // Central stable-definition dispatch avoids any refreshed-row activation transfer.
  function performControl(method: string, id: string, revision: int): void {
    if (!findAction(id, revision))
      return
    if (method === 'start')
      startAction(id, revision)
    else if (method === 'edit')
      editAction(id, revision)
    else if (method === 'remove')
      removeAction(id, revision)
  }
  // Remember a pointer target before asynchronous rows or checkouts change.
  function rememberAction(id: string, revision: int): void {
    pressedIdentity = actionIdentity(id, revision)
  }
  // Never transfer a pressed action to the new row or checkout on release.
  function releaseAction(id: string, revision: int): void {
    releaseControl('start', id, revision)
  }
  // The original pointer identity is mandatory for every definition effect.
  function releaseControl(method: string, id: string, revision: int): void {
    var remembered = pressedIdentity
    pressedIdentity = ''
    if (remembered === actionIdentity(id, revision))
      performControl(method, id, revision)
  }
  // Selecting retained history never reads a replacement row under an old press.
  function inspectHistory(run: var, pointer: bool): void {
    var identity = run ? [run.projectId, run.checkoutId, run.id, run.definitionRevision, run.definitionHash].join('|') : ''
    var pressed = pressedRunIdentity
    pressedRunIdentity = ''
    if (displayOnly || client.captureActive || client.pending || !run || !project || !checkout || run.projectId !== project.id || run.checkoutId !== checkout.id || pointer && pressed !== identity)
      return
    client.observeRun(run.id)
  }
  // Shared client submits only displayed approved revision for this exact checkout.
  function startAction(id: string, revision: int): void {
    if (displayOnly || client.captureActive || !checkout || !findAction(id, revision) || !executionAvailable || client.pending || client.submissionUncertain)
      return
    client.start(id, revision)
  }
  // Read only after binding capture, exact selection and view activity.
  function refresh(): void {
    if (displayOnly || client.captureActive || !active || !visible || !project)
      return
    if (editConflict)
      conflictRefreshPending = true
    client.refresh()
    client.checkAvailability()
  }
  // Explicit creation opens a local draft, with no backend or execution request.
  function addAction(): void {
    if (displayOnly || client.pending)
      return
    editor.begin(null, client.snapshot.revision)
    draftProjectId = project ? project.id : ''
    editConflict = false
    conflictRefreshed = false
    editing = true
  }
  // Edit only a stable displayed definition; retain its original store revision.
  function editAction(id: string, revision: int): void {
    var definition = findAction(id, revision)
    if (displayOnly || client.pending || !definition)
      return
    editor.begin(definition, client.snapshot.revision)
    draftProjectId = project.id
    editConflict = false
    conflictRefreshed = false
    editing = true
  }
  // User deliberately approves the retained draft over the freshly displayed state.
  function saveOverLatest(): void {
    if (displayOnly || client.captureActive || client.pending || !editConflict || !conflictRefreshed || !project || draftProjectId !== project.id || (editor.draft.id && !conflictDefinition))
      return
    editor.fieldError = editor.validate()
    if (editor.fieldError)
      return
    saving = true
    if (!client.configure(editor.definition(), conflictRevision))
      saving = false
  }
  // Refuse removal locally for every checkout's protected evidence; backend rechecks.
  function removeAction(id: string, revision: int): void {
    if (displayOnly || client.pending || !findAction(id, revision) || Records.runs(client.snapshot, project.id, '').some(function (r) {
      return r.actionId === id && Records.protectedRun(r)
    }))
      return
    client.remove(id, client.snapshot.revision)
  }
  // Presentation capture includes local observations, never serializes transport callbacks.
  function captureSnapshot(): var {
    return {
      selectedActionId: selectedActionId,
      helpExpanded: helpExpanded,
      selectedIdentity: selectedIdentity,
      editing: editing,
      editConflict: editConflict,
      conflictRefreshed: conflictRefreshed,
      conflictRevision: conflictRevision,
      draftProjectId: draftProjectId,
      editor: editor.captureSnapshot(),
      snapshot: client.snapshot,
      currentRun: client.currentRun,
      runId: client.runId,
      requestId: client.requestId,
      submissionUncertain: client.submissionUncertain,
      submissionTarget: client.submissionTarget,
      availability: client.availability,
      available: client.available,
      error: client.error,
      output: client.output,
      truncated: client.truncated
    }
  }
  // Restore observations/drafts without executing, reading or canceling native work.
  function captureRestore(saved: var): void {
    if (!saved)
      return
    helpExpanded = saved.helpExpanded === true
    selectedActionId = saved.selectedActionId || ''
    selectedIdentity = saved.selectedIdentity || ''
    editing = saved.editing === true
    editConflict = saved.editConflict === true
    conflictRefreshed = saved.conflictRefreshed === true
    conflictRefreshPending = false
    conflictRevision = saved.conflictRevision || 0
    draftProjectId = saved.draftProjectId || (project ? project.id : '')
    editor.captureRestore(saved.editor)
    client.snapshot = saved.snapshot || {
      revision: 0,
      definitions: [],
      runs: [],
      requests: []
    }
    client.currentRun = saved.currentRun || null
    client.runId = saved.runId || ''
    client.requestId = saved.requestId || ''
    client.submissionUncertain = saved.submissionUncertain === true
    client.submissionTarget = saved.submissionTarget || null
    client.availability = saved.availability || {}
    client.available = saved.available === true
    client.error = saved.error || null
    client.output = saved.output || ''
    client.truncated = saved.truncated === true
  }
  // Isolated capture fixture uses this same production content and client state.
  function captureReset(fixture: var): void {
    captureRestore(fixture && fixture.projectActions ? fixture.projectActions : {})
    if (!fixture || !fixture.projectActions || !fixture.projectActions.editor)
      editor.begin(null, client.snapshot.revision)
  }
  // Captures cannot queue a read that executes after capture restoration.
  function scheduleRefresh(): void {
    if (displayOnly || client.captureActive || !active || !visible || !project)
      return
    var token = client.generation
    var projectId = project.id
    var checkoutId = checkout ? checkout.id : ''
    Qt.callLater(function () {
      if (token === client.generation && actions.project && actions.project.id === projectId && (actions.checkout ? actions.checkout.id : '') === checkoutId)
        actions.refresh()
    })
  }
  onProjectChanged: {
    if (!project || project.id !== draftProjectId) {
      editing = false
      editConflict = false
      conflictRefreshed = false
    }
    scheduleRefresh()
  }
  onCheckoutChanged: scheduleRefresh()
  spacing: Style.space(8)
  Aranea.UiLabel {
    text: 'Workflow actions'
    font.bold: true
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    text: 'Save reusable tests, builds, and dev servers here. Opening a project does not run them.'
  }
  Aranea.ActionButton {
    objectName: 'actionHelpToggle'
    text: actions.helpExpanded ? 'Hide actions help' : 'How to use actions'
    pointerGate: actions.pointerGate
    onClicked: actions.helpExpanded = !actions.helpExpanded
  }
  Aranea.WorkflowHelp {
    Layout.fillWidth: true
    visible: actions.helpExpanded
    topic: 'actions'
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    text: 'Checkout: ' + (actions.checkout ? actions.checkout.path + ' · ' + actions.checkout.id : 'Selected checkout unavailable. Locate it before running.')
    technical: true
    wrapMode: Text.WrapAnywhere
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: !actions.executionAvailable
    text: 'Execution unavailable. Action configuration remains available. Refresh after restoring the user manager and required helpers.'
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: client.submissionUncertain
    text: 'Submission unconfirmed. Refresh to recover the exact receipt. Do not submit another run.'
    color: Aranea.DesignTokens.attention
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: !!client.error
    text: client.error ? (client.error.message || client.error.code) + (client.error.recovery ? ' ' + client.error.recovery : '') : ''
    color: Aranea.DesignTokens.attention
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  Flow {
    Layout.fillWidth: true
    spacing: Style.space(8)
    Aranea.ActionButton {
      text: 'Refresh actions'
      enabled: !actions.displayOnly && !client.pending
      pointerGate: actions.pointerGate
      onClicked: actions.refresh()
    }
    Aranea.ActionButton {
      text: 'Add action'
      enabled: !actions.displayOnly && !client.pending
      pointerGate: actions.pointerGate
      onClicked: actions.addAction()
    }
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: !actions.definitions.length
    text: 'No actions yet. Add action to define a test, build, or dev server. Examples are available in the editor.'
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  Repeater {
    model: actions.definitions
    ColumnLayout {
      id: action
      required property var modelData
      Layout.fillWidth: true
      Aranea.UiLabel {
        Layout.fillWidth: true
        text: action.modelData.name + ' · ' + (action.modelData.kind === 'service' ? 'Service' : 'Command')
        font.bold: true
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
      }
      Aranea.UiLabel {
        Layout.fillWidth: true
        text: action.modelData.argv.map(function (arg) {
          return JSON.stringify(arg)
        }).join(' ')
        technical: true
        wrapMode: Text.WrapAnywhere
      }
      Aranea.UiLabel {
        Layout.fillWidth: true
        text: 'Working folder: ' + action.modelData.cwdRelative
        technical: true
        wrapMode: Text.WrapAnywhere
      }
      Flow {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Aranea.ActionButton {
          text: 'Details'
          selected: actions.selectedActionId === action.modelData.id
          pointerGate: actions.pointerGate
          onClicked: actions.selectAction(action.modelData.id, action.modelData.revision)
        }
        Aranea.ActionButton {
          objectName: 'actionStart:' + action.modelData.id
          text: action.modelData.kind === 'service' ? 'Start' : 'Run'
          enabled: !actions.displayOnly && actions.executionAvailable && !!actions.checkout && !client.pending && !client.submissionUncertain && !Records.activeRun(client.snapshot, actions.project.id, actions.checkout.id, action.modelData.id)
          pointerGate: actions.pointerGate
          onPressed: actions.rememberAction(action.modelData.id, action.modelData.revision)
          onPressCanceled: actions.pressedIdentity = ''
          onClicked: {
            if (actions.pressedIdentity)
              actions.releaseAction(action.modelData.id, action.modelData.revision)
            else
              actions.activateAction(action.modelData.id, action.modelData.revision)
          }
        }
        Aranea.ActionButton {
          objectName: 'actionEdit:' + action.modelData.id
          text: 'Edit'
          enabled: !actions.displayOnly && !client.pending
          pointerGate: actions.pointerGate
          onPressed: actions.rememberAction(action.modelData.id, action.modelData.revision)
          onPressCanceled: actions.pressedIdentity = ''
          onClicked: {
            if (actions.pressedIdentity)
              actions.releaseControl('edit', action.modelData.id, action.modelData.revision)
            else
              actions.activateControl('edit', action.modelData.id, action.modelData.revision)
          }
        }
        Aranea.ActionButton {
          objectName: 'actionRemove:' + action.modelData.id
          text: 'Remove action'
          enabled: !actions.displayOnly && !client.pending && !Records.runs(client.snapshot, actions.project.id, '').some(function (r) {
            return r.actionId === action.modelData.id && Records.protectedRun(r)
          })
          pointerGate: actions.pointerGate
          onPressed: actions.rememberAction(action.modelData.id, action.modelData.revision)
          onPressCanceled: actions.pressedIdentity = ''
          onClicked: {
            if (actions.pressedIdentity)
              actions.releaseControl('remove', action.modelData.id, action.modelData.revision)
            else
              actions.activateControl('remove', action.modelData.id, action.modelData.revision)
          }
        }
      }
    }
  }
  ProjectActionEditor {
    id: editor
    Layout.fillWidth: true
    visible: actions.editing
    displayOnly: actions.displayOnly
    pending: client.pending
    pointerGate: actions.pointerGate
    onSaveRequested: function (definition, revision) {
      if (!actions.displayOnly && !client.captureActive && actions.project && actions.draftProjectId === actions.project.id) {
        actions.saving = true
        if (!client.configure(definition, revision))
          actions.saving = false
      }
    }
    onCancelRequested: actions.editing = false
  }
  ColumnLayout {
    Layout.fillWidth: true
    visible: actions.editing && actions.editConflict
    Aranea.UiLabel {
      Layout.fillWidth: true
      text: 'Draft retained. Refresh actions to review the latest saved definition before saving over it.'
      wrapMode: Text.WrapAtWordBoundaryOrAnywhere
    }
    Aranea.UiLabel {
      Layout.fillWidth: true
      visible: actions.conflictRefreshed
      text: !editor.draft.id ? 'State refreshed. Review your new action draft before retrying.' : actions.conflictDefinition ? 'Latest saved: ' + actions.conflictDefinition.name + ' · revision ' + actions.conflictDefinition.revision + ' · ' + actions.conflictDefinition.argv.map(function (arg) {
        return JSON.stringify(arg)
      }).join(' ') + ' · folder ' + actions.conflictDefinition.cwdRelative : 'This action was removed. Cancel and add a new action to configure it again.'
      wrapMode: Text.WrapAtWordBoundaryOrAnywhere
    }
    Aranea.ActionButton {
      text: 'Save draft over latest'
      enabled: !actions.displayOnly && !client.pending && actions.conflictRefreshed && (!editor.draft.id || !!actions.conflictDefinition)
      pointerGate: actions.pointerGate
      onClicked: actions.saveOverLatest()
    }
  }
  Aranea.UiLabel {
    text: 'Runs in this checkout'
    font.bold: true
    visible: actions.runs.length > 0
  }
  Repeater {
    model: actions.runs
    Aranea.ActionButton {
      id: retained
      required property var modelData
      text: (modelData.definitionSnapshot ? modelData.definitionSnapshot.name : modelData.id) + ' · ' + Records.runLabel(modelData)
      Layout.fillWidth: true
      selected: client.currentRun && client.currentRun.id === modelData.id
      enabled: !actions.displayOnly && !client.pending
      pointerGate: actions.pointerGate
      onPressed: actions.pressedRunIdentity = [modelData.projectId, modelData.checkoutId, modelData.id, modelData.definitionRevision, modelData.definitionHash].join('|')
      onPressCanceled: actions.pressedRunIdentity = ''
      onClicked: actions.inspectHistory(retained.modelData, !!actions.pressedRunIdentity)
    }
  }
  ProjectRunDetails {
    Layout.fillWidth: true
    client: client
    run: client.currentRun
    checkout: actions.checkout
    displayOnly: actions.displayOnly
    projectClient: actions.projectClient
    pointerGate: actions.pointerGate
  }
}
