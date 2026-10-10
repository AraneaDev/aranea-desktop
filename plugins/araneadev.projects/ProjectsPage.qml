// Friendly project registration and customization consume clients through typed requests.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

ColumnLayout {
  id: page
  // Registry read cache remains available without the live compositor owner.
  property var registryState: ({})
  // Installed supported editor and terminal choices from the probe.
  property var tools: ({})
  // Persistent scan client; page visibility never controls its lifetime.
  property var discoveryClient: null
  // Shared live-owner client supplies Open availability and progress.
  property var projectClient: null
  // Current details destination, supplied by Projects IPC or explicit selection.
  property string projectId: ''
  // Dedicated window supplies project selection outside the content.
  property bool sidebarNavigation: false
  // Focused project destination supplied by standalone navigation.
  property string viewSection: 'all'
  // Inert captures refuse all backend, chooser and owner actions.
  property bool displayOnly: false
  // Registry mutations are serialized by the focused operation client.
  property bool pending: false
  // Actionable backend error retained independently of discovery outcomes.
  property string error: ''
  // Shared pointer/layout settling gate.
  property var pointerGate: null
  // Toggle durable ignored review without rescanning.
  property bool ignoredExpanded: false
  // Guided setup is presentation state; saves use existing typed requests.
  property bool setupActive: false
  // Current zero-based stage in the local setup guide.
  property int setupStep: 0
  // Exact identity returned by this wizard’s successful registration.
  property string setupProjectId: ''
  // Distinct registered projects in the user's explicit checkout selection order.
  property var setupProjectIds: []
  // Current position follows exact identity, independent of registry ordering.
  readonly property int setupProjectIndex: setupProjectIds.indexOf(setupProjectId)
  // Any active mutation or scan pauses switching projects and wizard stages.
  readonly property bool setupNavigationPending: pending || !!discoveryClient && discoveryClient.pending || details.pending || details.actions.pending
  // Explicit submitted selection matched against successful readback.
  property var setupRegistrationPaths: []
  // A folder confirmation is awaiting canonical registry approval.
  property bool setupAwaitingFolder: false
  // Offline project help visibility.
  property bool helpExpanded: false
  // Agent setup help is reachable even before the Agents bar item appears.
  property string helpTopic: 'projects'
  // Optional folder management stays separate from the guided entry point.
  property bool foldersExpanded: false
  // Only completed saves and resolved tool choices permit forward progress.
  readonly property bool setupCanContinue: !setupNavigationPending && (setupStep === 0 ? (registryState.roots || []).length > 0 : setupStep === 1 ? !!selectedProject && candidates.selectedPaths.length === 0 : setupStep === 2 ? !!selectedProject && !details.dirty && !details.toolChoiceRequired && !details.actions.editing && !details.actions.pending : false)
  // Starting the guide never scans, saves, or opens applications.
  function startSetup(): void {
    if (displayOnly || setupNavigationPending || details.dirty || details.actions.editing)
      return
    setupActive = true
    setupStep = 0
    setupProjectId = ''
    setupProjectIds = []
    setupRegistrationPaths = []
    setupAwaitingFolder = false
    helpExpanded = false
    foldersExpanded = false
    candidates.selectedPaths = []
  }
  // Forward navigation changes presentation only after its guard passes.
  function advanceSetup(): void {
    if (displayOnly || !setupActive || !setupCanContinue)
      return
    if (setupStep === 2 && setupProjectIndex >= 0 && setupProjectIndex + 1 < setupProjectIds.length)
      setupProjectId = setupProjectIds[setupProjectIndex + 1]
    else
      setupStep = Math.min(3, setupStep + 1)
  }
  // Back cannot hide an unsaved configuration behind a new registration.
  function backSetup(): void {
    if (displayOnly || !setupActive || setupNavigationPending || setupStep === 2 && (details.dirty || details.actions.editing))
      return
    if (setupStep === 2 && setupProjectIndex > 0)
      setupProjectId = setupProjectIds[setupProjectIndex - 1]
    else
      setupStep = Math.max(0, setupStep - 1)
  }
  // Exit preserves saved registration and the exact configured project destination.
  function finishSetup(): void {
    if (!displayOnly && !setupNavigationPending) {
      var completedId = setupActive && selectedProject ? selectedProject.id : ''
      setupActive = false
      if (completedId)
        detailsRequested(completedId)
      setupRegistrationPaths = []
      setupAwaitingFolder = false
    }
  }
  // Only successful readback of this wizard's explicit request advances it.
  function registryMutationCompleted(action: string, args: var, state: var): void {
    if (displayOnly)
      return
    if (action === 'configure' && selectedProject && args.projectId === selectedProject.id)
      details.discardDraft()
    if (!setupActive)
      return
    if (action === 'root-add' && setupAwaitingFolder) {
      setupAwaitingFolder = false
      setupStep = 1
    }
    if (action !== 'register' || !setupRegistrationPaths.length || !args.paths || JSON.stringify(args.paths.slice().sort()) !== JSON.stringify(setupRegistrationPaths.slice().sort()))
      return
    var ids = []
    for (var i = 0; i < setupRegistrationPaths.length; i++) {
      var path = setupRegistrationPaths[i]
      var added = (state.projects || []).filter(function (project) {
        return (project.checkouts || []).some(function (checkout) {
          return checkout.path === path
        })
      })[0]
      if (!added)
        return
      if (ids.indexOf(added.id) < 0)
        ids.push(added.id)
    }
    setupProjectIds = setupProjectIds.concat(ids.filter(function (id) {
      return setupProjectIds.indexOf(id) < 0
    }))
    setupProjectId = ids[0]
    setupStep = 2
    setupRegistrationPaths = []
  }
  onErrorChanged: if (error) {
    setupRegistrationPaths = []
    setupAwaitingFolder = false
  }
  // Exact checkout whose latest owner outcome is shown, including separate opens.
  property string recoveryCheckoutId: ''
  // Saved selection observations reset recovery when its project/checkout changes.
  property string recoveryProjectId: ''
  // Last persisted default selection distinguishes refreshed records from actual selection changes.
  property string recoverySelectedCheckoutId: ''
  // Public explicit-selection contract for review consumers.
  property alias candidateList: candidates
  // Public detail draft boundary used by capture snapshot restoration.
  property alias details: details
  // Durable ignore metadata, including common-directory identity.
  readonly property var ignored: registryState.ignored || []
  // Partial scans keep their candidates available for explicit registration.
  readonly property bool partial: !!discoveryClient && discoveryClient.partial
  // Details resolve opaque identity against current saved registrations.
  readonly property var selectedProject: (registryState.projects || []).filter(function (p) {
    return p.id === (setupActive ? setupProjectId : projectId)
  })[0] || null
  // Emit one explicit selected registration batch.
  signal registerRequested(var paths)
  // Folder confirmation adds a discovery root before the client scans its ID.
  signal rootAddRequested(string path)
  // Removing a root does not remove any registered projects.
  signal rootRemoveRequested(string rootId)
  // Request a scan only after explicit refresh or choosing a folder.
  signal discoverRequested(string rootId)
  // Cancellation affects only the local discovery process group.
  signal cancelRequested
  // Durable ignore actions are applied by the backend, never the view.
  signal ignoreRequested(string path)
  // Unignore restores the durable group to the next explicit review.
  signal unignoreRequested(string path)
  // Configuration and checkouts are saved only by explicit actions.
  signal configureRequested(string projectId, var draft)
  // Explicit checkout preference is saved by the backend.
  signal checkoutRequested(string projectId, string checkoutId)
  // Confirm relocation after backend validation while preserving IDs.
  signal locateRequested(string projectId, string checkoutId, string path)
  // Remove only the saved registration.
  signal removeRequested(string projectId)
  // The sole owner handles Open and explicit role recovery.
  signal openRequested(var payload)
  // Route typed details destination through the Projects composition root.
  signal detailsRequested(string projectId)
  // Read current registry/tool/owner state after an actionable error.
  signal refreshRequested
  // Submission never occurs as a consequence of candidate selection.
  function addSelected(): void {
    if (!displayOnly && !pending && candidates.selectedPaths.length) {
      if (setupActive)
        setupRegistrationPaths = candidates.selectedPaths.slice()
      registerRequested(candidates.selectedPaths.slice())
    }
  }
  // Reconcile owner-wide operation snapshots rather than retaining this client's older result.
  function reconcileOperation(reported: var): void {
    var project = selectedProject
    var snapshot = projectClient ? projectClient.snapshot : {}
    if (!project || !projectClient || !projectClient.available || !snapshot.sessionId) {
      details.operation = null
      return
    }
    if (recoveryProjectId !== project.id || recoverySelectedCheckoutId !== project.lastCheckoutId) {
      recoveryProjectId = project.id
      recoverySelectedCheckoutId = project.lastCheckoutId || ''
      recoveryCheckoutId = project.lastCheckoutId || ''
    }
    var checkouts = project.checkouts || []
    if (reported && reported.sessionId === snapshot.sessionId && reported.projectId === project.id && checkouts.some(function (c) {
      return c.id === reported.checkoutId
    }))
      recoveryCheckoutId = reported.checkoutId
    var observations = (snapshot.operations || []).concat(reported ? [reported] : [])
    var latest = null
    for (var i = 0; i < observations.length; i++) {
      var operation = observations[i]
      if (!operation || operation.sessionId !== snapshot.sessionId || operation.projectId !== project.id || operation.checkoutId !== recoveryCheckoutId || !checkouts.some(function (c) {
        return c.id === operation.checkoutId
      }))
        continue
      if (!latest || (operation.generation || 0) > (latest.generation || 0) || (operation.generation || 0) === (latest.generation || 0) && (operation.completedAt || 0) >= (latest.completedAt || 0))
        latest = operation
    }
    details.operation = latest
  }
  onProjectClientChanged: reconcileOperation(null)
  onSelectedProjectChanged: reconcileOperation(null)
  // Save all presentation-only drafts and candidate selections for inert capture.
  function captureSnapshot(): var {
    return {
      selectedPaths: candidates.selectedPaths.slice(),
      setupActive: setupActive,
      setupStep: setupStep,
      setupProjectId: setupProjectId,
      setupProjectIds: setupProjectIds.slice(),
      setupRegistrationPaths: setupRegistrationPaths.slice(),
      setupAwaitingFolder: setupAwaitingFolder,
      helpExpanded: helpExpanded,
      helpTopic: helpTopic,
      foldersExpanded: foldersExpanded,
      ignoredExpanded: ignoredExpanded,
      detailsDraft: Object.assign({}, details.draft),
      actions: details.actions.captureSnapshot(),
      relocationDrafts: Object.assign({}, details.relocationDrafts),
      detailsOperation: details.operation,
      recoveryCheckoutId: recoveryCheckoutId,
      recoveryProjectId: recoveryProjectId,
      recoverySelectedCheckoutId: recoverySelectedCheckoutId,
      detailsDirty: details.dirty,
      customized: details.customized,
      folderPath: picker.pathDraft
    }
  }
  // Restore presentation only, with no registry read or owner request.
  function captureRestore(saved: var): void {
    if (!saved)
      return
    setupActive = saved.setupActive === true
    setupStep = saved.setupStep || 0
    setupProjectIds = saved.setupProjectIds || (saved.setupProjectId ? [saved.setupProjectId] : [])
    setupProjectId = saved.setupProjectId || ''
    setupRegistrationPaths = saved.setupRegistrationPaths || []
    setupAwaitingFolder = saved.setupAwaitingFolder === true
    helpExpanded = saved.helpExpanded === true
    helpTopic = saved.helpTopic === 'agents' ? 'agents' : 'projects'
    foldersExpanded = saved.foldersExpanded === true
    candidates.selectedPaths = saved.selectedPaths
    ignoredExpanded = saved.ignoredExpanded
    details.operation = saved.detailsOperation || null
    recoveryCheckoutId = saved.recoveryCheckoutId || (details.operation ? details.operation.checkoutId : '')
    recoveryProjectId = saved.recoveryProjectId || (selectedProject ? selectedProject.id : '')
    recoverySelectedCheckoutId = saved.recoverySelectedCheckoutId || (selectedProject ? selectedProject.lastCheckoutId || '' : '')
    details.relocationDrafts = saved.relocationDrafts || {}
    details.actions.captureRestore(saved.actions)
    details.draft = saved.detailsDraft
    details.dirty = saved.detailsDirty
    details.customized = saved.customized
    picker.pathDraft = saved.folderPath
  }
  // Reset local capture presentation using typed fixture data without backend access.
  function captureReset(fixture: var): void {
    setupActive = false
    setupStep = 0
    setupProjectId = ''
    setupProjectIds = []
    setupRegistrationPaths = []
    setupAwaitingFolder = false
    helpExpanded = false
    foldersExpanded = false
    candidates.selectedPaths = []
    ignoredExpanded = false
    details.discardDraft()
    details.actions.captureReset(fixture)
    details.relocationDrafts = {}
    details.operation = null
    details.customized = false
    picker.pathDraft = ''
    if (fixture && fixture.projectsDraft)
      captureRestore(fixture.projectsDraft)
  }
  spacing: Style.space(12)
  Aranea.PageHeader {
    visible: !page.sidebarNavigation
    title: 'Projects'
    description: 'Keep your editor, terminal, and workflow actions together for each project.'
  }
  RowLayout {
    Layout.fillWidth: true
    visible: !!page.error
    Aranea.UiLabel {
      Layout.fillWidth: true
      text: page.error
      color: Aranea.DesignTokens.attention
    }
    Aranea.ActionButton {
      text: 'Retry'
      enabled: !page.displayOnly && !page.pending
      pointerGate: page.pointerGate
      onClicked: page.refreshRequested()
    }
  }
  Flow {
    Layout.fillWidth: true
    spacing: Style.space(8)
    visible: !page.sidebarNavigation || !page.setupActive && page.viewSection === 'preferences'
    Aranea.ActionButton {
      objectName: 'projectSetupStart'
      text: 'Set up a project'
      visible: !page.setupActive && !page.sidebarNavigation
      enabled: !page.displayOnly && !page.setupNavigationPending && !details.dirty && !details.actions.editing
      pointerGate: page.pointerGate
      onClicked: page.startSetup()
    }
    Aranea.ActionButton {
      objectName: 'projectFoldersToggle'
      text: page.foldersExpanded ? 'Hide folder management' : 'Manage development folders'
      visible: !page.setupActive
      pointerGate: page.pointerGate
      onClicked: page.foldersExpanded = !page.foldersExpanded
    }
    Aranea.ActionButton {
      objectName: 'projectHelpToggle'
      visible: !page.sidebarNavigation
      text: page.helpExpanded && page.helpTopic === 'projects' ? 'Hide projects help' : 'Projects help'
      pointerGate: page.pointerGate
      onClicked: {
        page.helpExpanded = page.helpTopic === 'projects' ? !page.helpExpanded : true
        page.helpTopic = 'projects'
      }
    }
    Aranea.ActionButton {
      objectName: 'agentHelpToggle'
      visible: !page.sidebarNavigation
      text: page.helpExpanded && page.helpTopic === 'agents' ? 'Hide agent help' : 'Agent reporting help'
      pointerGate: page.pointerGate
      onClicked: {
        page.helpExpanded = page.helpTopic === 'agents' ? !page.helpExpanded : true
        page.helpTopic = 'agents'
      }
    }
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: !page.setupActive && (details.dirty || details.actions.editing)
    text: 'Save or discard your current draft before starting a new project setup.'
    color: Aranea.DesignTokens.attention
  }
  Aranea.WorkflowHelp {
    Layout.fillWidth: true
    visible: page.helpExpanded
    topic: page.helpTopic
  }
  ProjectSetupProgress {
    objectName: 'setupProgress'
    Layout.fillWidth: true
    visible: page.setupActive
    showControls: false
    displayOnly: page.displayOnly
    step: page.setupStep
    projectIndex: Math.max(0, page.setupProjectIndex)
    projectCount: page.setupProjectIds.length
    projectName: page.selectedProject ? page.selectedProject.name : ''
    canContinue: page.setupCanContinue
    canBack: page.setupStep !== 2 || !details.dirty && !details.actions.editing
    pending: page.setupNavigationPending
    pointerGate: page.pointerGate
    onBackRequested: page.backSetup()
    onNextRequested: page.advanceSetup()
    onFinishRequested: page.finishSetup()
    onCancelRequested: page.finishSetup()
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: page.setupActive && page.setupStep >= 2 && !page.selectedProject
    text: 'This project is no longer registered. Go Back to add it again, or Exit setup.'
    color: Aranea.DesignTokens.attention
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: page.setupActive && page.setupStep === 2 && (page.details.dirty || page.details.actions.editing)
    text: page.details.actions.editing ? 'Save or cancel the action draft before changing steps.' : 'Save preferences before changing steps, or Discard to keep the saved values.'
    color: Aranea.DesignTokens.attention
  }
  ColumnLayout {
    Layout.fillWidth: true
    visible: page.setupActive ? page.setupStep < 2 : (!page.sidebarNavigation || page.viewSection === 'preferences') && (page.foldersExpanded || candidates.candidates.length > 0)
    Aranea.UiLabel {
      Layout.fillWidth: true
      visible: !!page.discoveryClient && page.discoveryClient.pending
      text: 'Scanning for Git repositories… Review the results when the scan finishes.'
    }
    ProjectFolderPicker {
      id: picker
      objectName: 'projectFolderPicker'
      Layout.fillWidth: true
      visible: !page.setupActive || page.setupStep === 0
      displayOnly: page.displayOnly || page.pending || !!page.discoveryClient && page.discoveryClient.pending
      pointerGate: page.pointerGate
      onFolderRequested: function (path) {
        if (page.setupActive)
          page.setupAwaitingFolder = true
        page.rootAddRequested(path)
      }
    }
    Repeater {
      model: page.registryState.roots || []
      ColumnLayout {
        id: rootFolder
        required property var modelData
        Layout.fillWidth: true
        Aranea.UiLabel {
          Layout.fillWidth: true
          text: rootFolder.modelData.path
        }
        RowLayout {
          Aranea.ActionButton {
            text: 'Scan again'
            enabled: !page.displayOnly && !page.pending && !(page.discoveryClient && page.discoveryClient.pending)
            pointerGate: page.pointerGate
            onClicked: page.discoverRequested(rootFolder.modelData.id)
          }
          Aranea.ActionButton {
            text: 'Remove folder'
            visible: !page.setupActive
            enabled: !page.displayOnly && !page.pending
            pointerGate: page.pointerGate
            onClicked: page.rootRemoveRequested(rootFolder.modelData.id)
          }
        }
      }
    }
    Aranea.ActionButton {
      text: 'Cancel scan'
      visible: !!page.discoveryClient && page.discoveryClient.pending
      enabled: !page.displayOnly
      pointerGate: page.pointerGate
      onClicked: page.cancelRequested()
    }
    Aranea.UiLabel {
      Layout.fillWidth: true
      visible: page.partial
      text: 'Partial scan. Review the results or choose a narrower folder.'
    }
    Repeater {
      model: page.discoveryClient ? page.discoveryClient.errors : []
      Aranea.UiLabel {
        required property var modelData
        Layout.fillWidth: true
        text: typeof modelData === 'string' ? modelData : (modelData.message || modelData.code || 'Scan error') + (modelData.path ? ' · ' + modelData.path : '')
      }
    }
    Aranea.UiLabel {
      Layout.fillWidth: true
      visible: (!page.setupActive || page.setupStep === 1) && !!page.discoveryClient && !page.discoveryClient.pending && !candidates.candidates.length
      text: 'No repositories to review. Choose another folder or refresh an approved folder.'
    }
    ProjectCandidateList {
      id: candidates
      visible: !page.setupActive || page.setupStep === 1
      Layout.fillWidth: true
      candidates: page.discoveryClient ? page.discoveryClient.candidates.filter(function (c) {
        return !page.ignored.some(function (i) {
          return i.path === c.path || i.commonDir === c.commonDir
        }) && candidates.paths(c).length > 0
      }) : []
      registeredPaths: (page.registryState.projects || []).reduce(function (paths, p) {
        return paths.concat((p.checkouts || []).map(function (c) {
          return c.path
        }))
      }, [])
      displayOnly: page.displayOnly || page.pending
      pointerGate: page.pointerGate
      onIgnoreRequested: function (path) {
        page.ignoreRequested(path)
      }
    }
    Aranea.ActionButton {
      objectName: 'setupRegister'
      text: 'Add selected' + (candidates.selectedPaths.length ? ' (' + candidates.selectedPaths.length + ')' : '')
      visible: !page.setupActive || page.setupStep === 1
      enabled: !page.displayOnly && !page.pending && candidates.selectedPaths.length > 0
      pointerGate: page.pointerGate
      onClicked: page.addSelected()
    }
    Aranea.ActionButton {
      visible: !page.setupActive
      text: page.ignoredExpanded ? 'Hide ignored repositories' : 'Review ignored repositories'
      pointerGate: page.pointerGate
      onClicked: page.ignoredExpanded = !page.ignoredExpanded
    }
    ColumnLayout {
      Layout.fillWidth: true
      visible: !page.setupActive && page.ignoredExpanded
      Repeater {
        model: page.ignored
        ColumnLayout {
          id: ignoredRepo
          required property var modelData
          Layout.fillWidth: true
          Aranea.UiLabel {
            Layout.fillWidth: true
            text: ignoredRepo.modelData.path
          }
          Aranea.ActionButton {
            text: 'Unignore'
            enabled: !page.displayOnly && !page.pending
            pointerGate: page.pointerGate
            onClicked: page.unignoreRequested(ignoredRepo.modelData.path)
          }
        }
      }
    }
  }
  ColumnLayout {
    Layout.fillWidth: true
    visible: !page.setupActive && !page.sidebarNavigation
    Aranea.UiLabel {
      visible: (page.registryState.projects || []).length > 0
      text: 'Registered projects'
      font.bold: true
    }
    Repeater {
      model: page.registryState.projects || []
      ColumnLayout {
        id: project
        required property var modelData
        Layout.fillWidth: true
        Aranea.UiLabel {
          Layout.fillWidth: true
          text: project.modelData.name + ' · ' + (project.modelData.checkouts.length ? project.modelData.checkouts[0].path : '')
        }
        Aranea.ActionButton {
          text: 'Preferences & actions'
          selected: page.projectId === project.modelData.id
          pointerGate: page.pointerGate
          onClicked: page.detailsRequested(project.modelData.id)
        }
        Aranea.ActionButton {
          text: 'Open project'
          enabled: !page.displayOnly && !page.pending && !!page.projectClient && page.projectClient.available && !page.projectClient.pending && !!page.projectClient.snapshot.availability && page.projectClient.snapshot.availability.compositor === true
          pointerGate: page.pointerGate
          onClicked: page.openRequested({
            projectId: project.modelData.id
          })
        }
      }
    }
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: !page.setupActive && !!page.projectId && !page.selectedProject
    text: 'Project unavailable. Refresh or choose a registered project.'
  }
  ProjectDetails {
    id: details
    Layout.fillWidth: true
    visible: !!page.selectedProject && (page.setupActive ? page.setupStep === 2 : ['all', 'overview', 'actions', 'preferences'].indexOf(page.viewSection) >= 0)
    project: page.selectedProject
    headerProvided: page.sidebarNavigation
    guidedSetup: page.setupActive
    viewSection: page.viewSection
    projectClient: page.projectClient
    actionsActive: page.visible && details.visible && !page.displayOnly
    tools: page.tools
    displayOnly: page.displayOnly
    pending: page.pending || !!page.projectClient && page.projectClient.pending
    openAvailable: !!page.projectClient && page.projectClient.available && !!page.projectClient.snapshot.availability && page.projectClient.snapshot.availability.compositor === true
    pointerGate: page.pointerGate
    onConfigureRequested: function (id, draft) {
      page.configureRequested(id, draft)
    }
    onCheckoutRequested: function (id, checkout) {
      page.checkoutRequested(id, checkout)
    }
    onLocateRequested: function (id, checkout, path) {
      page.locateRequested(id, checkout, path)
    }
    onRemoveRequested: function (id) {
      page.removeRequested(id)
    }
    onOpenRequested: function (payload) {
      page.openRequested(payload)
    }
  }
  Aranea.WorkflowHelp {
    Layout.fillWidth: true
    visible: page.setupActive && page.setupStep === 3
    topic: 'agents'
    title: 'Connect agent reporting (optional)'
  }
  ProjectSetupProgress {
    Layout.fillWidth: true
    visible: page.setupActive
    showSteps: false
    displayOnly: page.displayOnly
    step: page.setupStep
    projectIndex: Math.max(0, page.setupProjectIndex)
    projectCount: page.setupProjectIds.length
    projectName: page.selectedProject ? page.selectedProject.name : ''
    canContinue: page.setupCanContinue
    canBack: page.setupStep !== 2 || !details.dirty && !details.actions.editing
    pending: page.setupNavigationPending
    pointerGate: page.pointerGate
    onBackRequested: page.backSetup()
    onNextRequested: page.advanceSetup()
    onFinishRequested: page.finishSetup()
    onCancelRequested: page.finishSetup()
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: !page.sidebarNavigation && !page.setupActive && !(page.registryState.projects || []).length && !candidates.candidates.length
    text: 'No projects yet. Set up a project to choose a Git checkout, your tools, and optional workflow actions.'
  }
  Connections {
    target: page.projectClient
    function onOperationChanged(operation) {
      page.reconcileOperation(operation)
    }
    function onSnapshotChanged() {
      page.reconcileOperation(null)
    }
    function onAvailableChanged() {
      page.reconcileOperation(null)
    }
  }
}
