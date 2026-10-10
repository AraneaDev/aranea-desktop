// Project presentation drafts emit typed configuration and live-owner requests.
pragma ComponentBehavior: Bound
// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "../araneadev.shared" as Aranea

ColumnLayout {
  id: details
  // Fresh saved registration; Open resolves these preferences through the owner.
  property var project: null
  // Installed supported tool observations from the backend probe.
  property var tools: ({})
  // Latest observed live-owner operation, including individual role outcomes.
  property var operation: null
  // Whether the live compositor is available; registration remains usable otherwise.
  property bool openAvailable: true
  // Prevent backend requests in capture and while a mutation is pending.
  property bool displayOnly: false
  // Shared pending indicator disables actions without owning operations.
  property bool pending: false
  // Shared pointer/layout settling gate.
  property var pointerGate: null
  // Existing project focus authority, shared with exact-run controls.
  property var projectClient: null
  // The surrounding selected page enables visible-only observation.
  property bool actionsActive: false
  // Public presentation/client boundary for capture and isolated fixtures.
  property alias actions: actions
  // Optional preferences stay collapsed after installed defaults resolve.
  property bool customized: false
  // Guided setup exposes preferences while deferring maintenance controls.
  property bool guidedSetup: false
  // Standalone navigation chooses one focused section; direct consumers retain all.
  property string viewSection: 'all'
  // Standalone window supplies identity and its single primary Open action.
  property bool headerProvided: false
  // Draft values never become saved configuration until explicit Apply.
  property var draft: ({})
  // Dirty drafts survive asynchronous observation refreshes.
  property bool dirty: false
  // Identity whose local draft is currently being edited.
  property string draftProjectId: ''
  // Locate-folder presentation drafts survive delegate recreation under stable identities.
  property var relocationDrafts: ({})
  // Show installed tool choices whenever saved adapters are missing or unavailable.
  readonly property bool toolChoiceRequired: !supported('editors', project && project.tools ? project.tools.editorId || (tools.defaults || {}).editorId : null) || !supported('terminals', project && project.tools ? project.tools.terminalId || (tools.defaults || {}).terminalId : null)
  // Explicit backend configuration request.
  signal configureRequested(string projectId, var draft)
  // Typed sole-owner request; no launch queue or binding state lives in this view.
  signal openRequested(var payload)
  // Explicit checkout selection is durable and independent of Open.
  signal checkoutRequested(string projectId, string checkoutId)
  // Relocation preserves IDs and never deletes checkout folders.
  signal locateRequested(string projectId, string checkoutId, string path)
  // Removing registration never closes windows or deletes repository files.
  signal removeRequested(string projectId)
  // Edit one exact checkout relocation draft without persisting or launching anything.
  function setRelocationDraft(projectId: string, checkoutId: string, path: string): void {
    if (!project || project.id !== projectId || !(project.checkouts || []).some(function (c) {
      return c.id === checkoutId
    }))
      return
    var key = projectId + ':' + checkoutId
    if (relocationDrafts[key] === path)
      return
    var next = Object.assign({}, relocationDrafts)
    next[key] = path
    relocationDrafts = next
  }
  // Return installed supported choices only.
  function choices(role: string): var {
    return (tools[role] || []).filter(function (t) {
      return t.available === true && t.supported === true
    })
  }
  // Verify a saved or drafted adapter against actual installed supported choices.
  function supported(role: string, id: var): bool {
    return choices(role).some(function (t) {
      return t.id === id
    })
  }
  // Initialize configuration drafts using saved preferences then supported defaults.
  function discardDraft(): void {
    var p = project || {}
    var saved = p.tools || {}
    var defaults = tools.defaults || {}
    draft = {
      name: p.name || '',
      editorId: saved.editorId || defaults.editorId || '',
      terminalId: saved.terminalId || defaults.terminalId || '',
      workspaceMode: p.workspaceMode || 'dedicated'
    }
    dirty = false
  }
  // Edit one allowlisted presentation value without invoking any client.
  function setDraft(key: string, value: string): void {
    if (['name', 'editorId', 'terminalId', 'workspaceMode'].indexOf(key) < 0 || displayOnly)
      return
    var next = Object.assign({}, draft)
    next[key] = value
    draft = next
    dirty = true
  }
  // Save only valid chosen adapters and workspace mode through the backend client.
  function applyDraft(): void {
    if (displayOnly || pending || !project || !draft.name || !supported('editors', draft.editorId) || !supported('terminals', draft.terminalId) || ['dedicated', 'current'].indexOf(draft.workspaceMode) < 0)
      return
    configureRequested(project.id, Object.assign({}, draft))
  }
  // Ordinary Open deliberately omits all unsaved presentation draft values.
  function openProject(): void {
    if (!displayOnly && !pending && project && openAvailable)
      openRequested({
        projectId: project.id
      })
  }
  // Recovery is offered only for the corresponding reported owner role outcome.
  function recoveryAllowed(role: string, kind: string): bool {
    if (!project || !operation || operation.projectId !== project.id || operation.state !== 'completed' || !(project.checkouts || []).some(function (c) {
      return c.id === operation.checkoutId
    }))
      return false
    var steps = (operation.steps || []).filter(function (s) {
      return s.role === role
    })
    var step = steps.length ? steps[steps.length - 1] : null
    if (kind === 'reobserve')
      return !!step && step.status === 'unconfirmed' && step.reobserveAvailable === true
    return !!step && (kind === 'retry' ? ['failed', 'missing'].indexOf(step.status) >= 0 : ['unconfirmed', 'uncertain'].indexOf(step.status) >= 0)
  }
  // Explicit recovery requests do not retry ordinary Open automatically.
  function recover(role: string, kind: string): void {
    if (displayOnly || pending || !openAvailable || !project || !recoveryAllowed(role, kind))
      return
    var request = {
      projectId: project.id,
      checkoutId: operation.checkoutId
    }
    if (operation.separate === true)
      request.separate = true
    if (operation.useCurrentWorkspace === true)
      request.useCurrentWorkspace = true
    request[kind === 'retry' ? 'retryRole' : kind === 'reobserve' ? 'reobserveRole' : 'newWindowRole'] = role
    openRequested(request)
  }
  onProjectChanged: if (!dirty || !project || draftProjectId !== project.id) {
    if (!project || draftProjectId !== project.id)
      operation = null
    discardDraft()
    draftProjectId = project ? project.id : ''
  }
  onToolsChanged: if (!dirty)
    discardDraft()
  Component.onCompleted: discardDraft()
  spacing: Style.space(8)
  visible: !!project
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: !details.headerProvided || details.guidedSetup
    text: details.project ? details.project.name : ''
    font.bold: true
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: !details.headerProvided || !!details.operation || !details.openAvailable
    text: !details.openAvailable ? 'Workspace opening unavailable. Restore the project owner and compositor, then retry.' : details.operation ? 'Open · ' + (details.operation.outcome || details.operation.state) : 'Open uses saved preferences.'
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: details.viewSection === 'overview' && !details.headerProvided
    text: {
      var p = details.project || {}, co = (p.checkouts || []).filter(function (c) {
        return c.id === p.lastCheckoutId
      })[0] || (p.checkouts || [])[0]
      return co ? co.path + '\nBranch: ' + (co.branch || 'detached') + ' · ' + (p.workspaceMode === 'current' ? 'Current workspace' : 'Dedicated workspace') : 'No registered checkout.'
    }
    technical: true
  }
  Flow {
    Layout.fillWidth: true
    spacing: Style.space(8)
    visible: details.viewSection === 'overview' && !details.headerProvided
    Repeater {
      model: ['editor', 'terminal']
      Aranea.ActionButton {
        required property string modelData
        text: 'New ' + modelData + ' window'
        enabled: !details.displayOnly && !details.pending && details.openAvailable
        pointerGate: details.pointerGate
        onClicked: details.openRequested({
          projectId: details.project.id,
          newWindowRole: modelData
        })
      }
    }
  }
  ProjectSectionCard {
    Layout.fillWidth: true
    visible: details.headerProvided && !details.guidedSetup && details.viewSection === 'overview'
    Aranea.UiLabel {
      text: 'Workspace'
      font.pixelSize: Style.font.body
      font.bold: true
    }
    Aranea.UiLabel {
      Layout.fillWidth: true
      text: 'Open your editor and terminal together. Existing project windows are reused when available.'
      opacity: 0.75
    }
    GridLayout {
      Layout.fillWidth: true
      columns: width < Style.space(360) ? 1 : 2
      columnSpacing: Style.space(24)
      rowSpacing: Style.space(12)
      Repeater {
        model: ['editors', 'terminals']
        ColumnLayout {
          required property string modelData
          Layout.fillWidth: true
          Aranea.UiLabel {
            text: parent.modelData === 'editors' ? 'EDITOR' : 'TERMINAL'
            opacity: 0.55
          }
          Aranea.UiLabel {
            Layout.fillWidth: true
            text: {
              var role = parent.modelData, id = details.project && details.project.tools ? details.project.tools[role === 'editors' ? 'editorId' : 'terminalId'] : ''
              id = id || (details.tools.defaults || {})[role === 'editors' ? 'editorId' : 'terminalId']
              var tool = (details.tools[role] || []).filter(function (t) {
                return t.id === id
              })[0]
              return tool ? tool.label : id || 'Choose in Preferences'
            }
            font.pixelSize: Style.font.body
          }
        }
      }
    }
    Flow {
      Layout.fillWidth: true
      spacing: Style.space(8)
      Repeater {
        model: ['editor', 'terminal']
        Aranea.ActionButton {
          required property string modelData
          text: 'New ' + modelData + ' window'
          enabled: !details.displayOnly && !details.pending && details.openAvailable
          pointerGate: details.pointerGate
          onClicked: details.openRequested({
            projectId: details.project.id,
            newWindowRole: modelData
          })
        }
      }
    }
    Aranea.UiLabel {
      Layout.fillWidth: true
      text: 'Change tools, checkouts, and workspace behavior in Preferences.'
      opacity: 0.55
    }
  }
  Aranea.UiLabel {
    objectName: 'projectOperationError'
    Layout.fillWidth: true
    visible: !!details.operation && !!details.operation.error
    text: details.operation && details.operation.error ? details.operation.error.message + (details.operation.error.recovery ? ' ' + details.operation.error.recovery : '') : ''
    color: Aranea.DesignTokens.attention
  }
  Aranea.ActionButton {
    visible: !details.headerProvided || details.guidedSetup
    text: details.pending ? 'Preparing…' : 'Open project'
    enabled: !details.displayOnly && !details.pending && details.openAvailable
    pointerGate: details.pointerGate
    onClicked: details.openProject()
  }
  Aranea.ActionButton {
    visible: !details.guidedSetup && details.viewSection === 'all'
    text: details.customized ? 'Hide preferences' : 'Project preferences'
    pointerGate: details.pointerGate
    onClicked: details.customized = !details.customized
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: details.toolChoiceRequired
    text: 'Choose an installed supported editor and terminal, then Save preferences.'
  }
  ProjectSectionCard {
    Layout.fillWidth: true
    visible: details.guidedSetup || details.viewSection === 'preferences' || details.viewSection === 'all' && (details.customized || details.toolChoiceRequired)
    Aranea.UiLabel {
      text: 'Project name'
    }
    Ui.TextField {
      Layout.fillWidth: true
      text: details.draft.name || ''
      enabled: !details.displayOnly
      Accessible.name: 'Project name'
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.body
      onTextEdited: details.setDraft('name', text)
    }
    Aranea.UiLabel {
      text: 'Editor'
    }
    Repeater {
      model: details.choices('editors')
      Aranea.ActionButton {
        id: editor
        required property var modelData
        text: modelData.label
        selected: details.draft.editorId === modelData.id
        enabled: !details.displayOnly
        pointerGate: details.pointerGate
        onClicked: details.setDraft('editorId', editor.modelData.id)
      }
    }
    Aranea.UiLabel {
      text: 'Terminal'
    }
    Repeater {
      model: details.choices('terminals')
      Aranea.ActionButton {
        id: terminal
        required property var modelData
        text: modelData.label
        selected: details.draft.terminalId === modelData.id
        enabled: !details.displayOnly
        pointerGate: details.pointerGate
        onClicked: details.setDraft('terminalId', terminal.modelData.id)
      }
    }
    Aranea.ActionButton {
      text: 'Dedicated workspace'
      selected: details.draft.workspaceMode === 'dedicated'
      enabled: !details.displayOnly
      pointerGate: details.pointerGate
      onClicked: details.setDraft('workspaceMode', 'dedicated')
    }
    Aranea.ActionButton {
      text: 'Use current workspace'
      selected: details.draft.workspaceMode === 'current'
      enabled: !details.displayOnly
      pointerGate: details.pointerGate
      onClicked: details.setDraft('workspaceMode', 'current')
    }
    RowLayout {
      Aranea.ActionButton {
        text: 'Save preferences'
        enabled: !details.displayOnly && !details.pending && details.supported('editors', details.draft.editorId) && details.supported('terminals', details.draft.terminalId)
        pointerGate: details.pointerGate
        onClicked: details.applyDraft()
      }
      Aranea.ActionButton {
        text: 'Discard'
        pointerGate: details.pointerGate
        onClicked: details.discardDraft()
      }
    }
    Repeater {
      model: details.project ? details.project.checkouts : []
      ColumnLayout {
        id: checkout
        required property var modelData
        Layout.fillWidth: true
        Aranea.UiLabel {
          Layout.fillWidth: true
          text: checkout.modelData.path + ' · ' + checkout.modelData.branch
        }
        Aranea.ActionButton {
          text: 'Use checkout'
          enabled: !details.displayOnly && !details.pending
          selected: details.project && details.project.lastCheckoutId === checkout.modelData.id
          pointerGate: details.pointerGate
          onClicked: details.checkoutRequested(details.project.id, checkout.modelData.id)
        }
        Aranea.ActionButton {
          text: 'Open separately'
          enabled: !details.displayOnly && !details.pending && details.openAvailable
          pointerGate: details.pointerGate
          onClicked: details.openRequested({
            projectId: details.project.id,
            checkoutId: checkout.modelData.id,
            separate: true
          })
        }
        ProjectFolderPicker {
          visible: !details.guidedSetup
          objectName: 'locateFolder:' + details.project.id + ':' + checkout.modelData.id
          buttonText: 'Locate folder'
          externalDraft: true
          pathDraft: details.relocationDrafts[details.project.id + ':' + checkout.modelData.id] || ''
          onPathEdited: function (path) {
            details.setRelocationDraft(details.project.id, checkout.modelData.id, path)
          }
          Layout.fillWidth: true
          displayOnly: details.displayOnly || details.pending
          pointerGate: details.pointerGate
          onFolderRequested: function (path) {
            details.locateRequested(details.project.id, checkout.modelData.id, path)
          }
        }
      }
    }
    Aranea.UiLabel {
      Layout.fillWidth: true
      visible: !details.guidedSetup
      text: 'Remove registration keeps repository files and existing windows.'
    }
    Aranea.ActionButton {
      visible: !details.guidedSetup
      text: 'Remove registration'
      enabled: !details.displayOnly && !details.pending
      pointerGate: details.pointerGate
      onClicked: details.removeRequested(details.project.id)
    }
  }
  Repeater {
    model: ['editor', 'terminal']
    RowLayout {
      id: role
      required property string modelData
      visible: details.recoveryAllowed(modelData, 'retry') || details.recoveryAllowed(modelData, 'new')
      Aranea.ActionButton {
        text: 'Retry ' + role.modelData
        visible: details.recoveryAllowed(role.modelData, 'retry')
        enabled: !details.displayOnly && !details.pending
        pointerGate: details.pointerGate
        onClicked: details.recover(role.modelData, 'retry')
      }
      Aranea.ActionButton {
        objectName: 'reobserveRole:' + role.modelData
        text: 'Check ' + role.modelData + ' again'
        visible: details.recoveryAllowed(role.modelData, 'reobserve')
        enabled: !details.displayOnly && !details.pending
        pointerGate: details.pointerGate
        onClicked: details.recover(role.modelData, 'reobserve')
      }
      Aranea.ActionButton {
        text: 'Open new ' + role.modelData + ' window'
        visible: details.recoveryAllowed(role.modelData, 'new')
        enabled: !details.displayOnly && !details.pending
        pointerGate: details.pointerGate
        onClicked: details.recover(role.modelData, 'new')
      }
    }
  }
  ProjectActions {
    id: actions
    Layout.fillWidth: true
    project: details.project
    projectClient: details.projectClient
    visible: details.guidedSetup || details.viewSection === 'all' || details.viewSection === 'actions'
    active: details.actionsActive && visible
    displayOnly: details.displayOnly
    pointerGate: details.pointerGate
  }
}
