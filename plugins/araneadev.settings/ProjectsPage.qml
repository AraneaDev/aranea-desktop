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
  // Current details destination, supplied by Settings IPC or explicit selection.
  property string projectId: ''
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
    return p.id === projectId
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
  // Route typed details destination through the Settings composition root.
  signal detailsRequested(string projectId)
  // Read current registry/tool/owner state after an actionable error.
  signal refreshRequested
  // Submission never occurs as a consequence of candidate selection.
  function addSelected(): void {
    if (!displayOnly && !pending && candidates.selectedPaths.length)
      registerRequested(candidates.selectedPaths.slice())
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
      ignoredExpanded: ignoredExpanded,
      detailsDraft: Object.assign({}, details.draft),
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
    candidates.selectedPaths = saved.selectedPaths
    ignoredExpanded = saved.ignoredExpanded
    details.operation = saved.detailsOperation || null
    recoveryCheckoutId = saved.recoveryCheckoutId || (details.operation ? details.operation.checkoutId : '')
    recoveryProjectId = saved.recoveryProjectId || (selectedProject ? selectedProject.id : '')
    recoverySelectedCheckoutId = saved.recoverySelectedCheckoutId || (selectedProject ? selectedProject.lastCheckoutId || '' : '')
    details.relocationDrafts = saved.relocationDrafts || {}
    details.draft = saved.detailsDraft
    details.dirty = saved.detailsDirty
    details.customized = saved.customized
    picker.pathDraft = saved.folderPath
  }
  // Reset local capture presentation using typed fixture data without backend access.
  function captureReset(fixture: var): void {
    candidates.selectedPaths = []
    ignoredExpanded = false
    details.discardDraft()
    details.relocationDrafts = {}
    details.operation = null
    details.customized = false
    picker.pathDraft = ''
    if (fixture && fixture.projectsDraft)
      captureRestore(fixture.projectsDraft)
  }
  spacing: Style.space(12)
  SettingsPageHeader {
    title: 'Projects'
    description: 'Choose a development folder, review repositories and Add selected. Open resumes saved tools in a project workspace.'
  }
  RowLayout {
    Layout.fillWidth: true
    visible: !!page.error
    SettingsLabel {
      Layout.fillWidth: true
      text: page.error
      color: Aranea.DesignTokens.attention
    }
    SettingsButton {
      text: 'Retry'
      enabled: !page.displayOnly && !page.pending
      pointerGate: page.pointerGate
      onClicked: page.refreshRequested()
    }
  }
  ProjectFolderPicker {
    id: picker
    Layout.fillWidth: true
    displayOnly: page.displayOnly || page.pending || !!page.discoveryClient && page.discoveryClient.pending
    pointerGate: page.pointerGate
    onFolderRequested: function (path) {
      page.rootAddRequested(path)
    }
  }
  Repeater {
    model: page.registryState.roots || []
    ColumnLayout {
      id: rootFolder
      required property var modelData
      Layout.fillWidth: true
      SettingsLabel {
        Layout.fillWidth: true
        text: rootFolder.modelData.path
      }
      RowLayout {
        SettingsButton {
          text: 'Refresh'
          enabled: !page.displayOnly && !page.pending && !(page.discoveryClient && page.discoveryClient.pending)
          pointerGate: page.pointerGate
          onClicked: page.discoverRequested(rootFolder.modelData.id)
        }
        SettingsButton {
          text: 'Remove folder'
          enabled: !page.displayOnly && !page.pending
          pointerGate: page.pointerGate
          onClicked: page.rootRemoveRequested(rootFolder.modelData.id)
        }
      }
    }
  }
  SettingsButton {
    text: 'Cancel scan'
    visible: !!page.discoveryClient && page.discoveryClient.pending
    enabled: !page.displayOnly
    pointerGate: page.pointerGate
    onClicked: page.cancelRequested()
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: page.partial
    text: 'Partial scan. Review the results or choose a narrower folder.'
  }
  Repeater {
    model: page.discoveryClient ? page.discoveryClient.errors : []
    SettingsLabel {
      required property var modelData
      Layout.fillWidth: true
      text: typeof modelData === 'string' ? modelData : (modelData.message || modelData.code || 'Scan error') + (modelData.path ? ' · ' + modelData.path : '')
    }
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !!page.discoveryClient && !page.discoveryClient.pending && !candidates.candidates.length
    text: 'No repositories to review. Choose another folder or refresh an approved folder.'
  }
  ProjectCandidateList {
    id: candidates
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
  SettingsButton {
    text: 'Add selected'
    enabled: !page.displayOnly && !page.pending && candidates.selectedPaths.length > 0
    pointerGate: page.pointerGate
    onClicked: page.addSelected()
  }
  SettingsButton {
    text: page.ignoredExpanded ? 'Hide ignored repositories' : 'Review ignored repositories'
    pointerGate: page.pointerGate
    onClicked: page.ignoredExpanded = !page.ignoredExpanded
  }
  ColumnLayout {
    Layout.fillWidth: true
    visible: page.ignoredExpanded
    Repeater {
      model: page.ignored
      ColumnLayout {
        id: ignoredRepo
        required property var modelData
        Layout.fillWidth: true
        SettingsLabel {
          Layout.fillWidth: true
          text: ignoredRepo.modelData.path
        }
        SettingsButton {
          text: 'Unignore'
          enabled: !page.displayOnly && !page.pending
          pointerGate: page.pointerGate
          onClicked: page.unignoreRequested(ignoredRepo.modelData.path)
        }
      }
    }
  }
  SettingsLabel {
    text: 'Registered projects'
    font.bold: true
  }
  Repeater {
    model: page.registryState.projects || []
    ColumnLayout {
      id: project
      required property var modelData
      Layout.fillWidth: true
      SettingsLabel {
        Layout.fillWidth: true
        text: project.modelData.name + ' · ' + (project.modelData.checkouts.length ? project.modelData.checkouts[0].path : '')
      }
      SettingsButton {
        text: 'Details'
        selected: page.projectId === project.modelData.id
        pointerGate: page.pointerGate
        onClicked: page.detailsRequested(project.modelData.id)
      }
      SettingsButton {
        text: 'Open'
        enabled: !page.displayOnly && !page.pending && !!page.projectClient && page.projectClient.available && !page.projectClient.pending && !!page.projectClient.snapshot.availability && page.projectClient.snapshot.availability.compositor === true
        pointerGate: page.pointerGate
        onClicked: page.openRequested({
          projectId: project.modelData.id
        })
      }
    }
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !!page.projectId && !page.selectedProject
    text: 'Project unavailable. Refresh or choose a registered project.'
  }
  ProjectDetails {
    id: details
    Layout.fillWidth: true
    project: page.selectedProject
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
