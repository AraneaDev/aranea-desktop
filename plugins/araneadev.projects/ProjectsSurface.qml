// Standalone project workspace with persistent drafts and responsive navigation.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "AgentSuggestion.js" as Suggestion
import "ProjectsNavigation.js" as Navigation
import "ProjectOverview.js" as Overview
import "ProjectProfiles.js" as Profiles

Item {
  id: panel
  // Persistent presentation entry owns clients and visibility.
  required property var root
  // Minute clock updates reset and stale usage explanations while visible.
  property real nowMs: Date.now()
  // Deferred viewport changes belong to their original live observation epoch.
  function scheduleGitBackground() {
    if (!visible || !root.opened || root.inert)
      return
    var epoch = root.gitClient.epoch
    Qt.callLater(function () {
      if (panel.root.gitClient.epoch === epoch)
        panel.queueGitBackground()
    })
  }
  // Refresh only actual visible rows plus a bounded tail of recently visited projects.
  function queueGitBackground() {
    if (!visible || !root.opened || root.inert)
      return
    var projects = root.projectController.state.projects || []
    var visits = (root.projectController.state.navigation || {}).visitedAt || {}
    var ids = sidebar.visibleProjectIds()
    Object.keys(visits).filter(function (id) {
      return visits[id] > 0
    }).sort(function (a, b) {
      return visits[b] - visits[a]
    }).some(function (id) {
      if (ids.indexOf(id) < 0)
        ids.push(id)
      return ids.length >= 12
    })
    var targets = []
    ids.slice(0, 12).forEach(function (id) {
      var project = projects.find(function (p) {
        return p.id === id
      })
      if (project && (project.checkouts || []).some(function (checkout) {
        return checkout.id === project.lastCheckoutId
      }))
        targets.push({
          projectId: id,
          checkoutId: project.lastCheckoutId
        })
    })
    root.gitClient.queueBackground(targets)
  }
  Timer {
    interval: 10000
    repeat: true
    running: panel.visible && panel.root.opened && !panel.root.inert
    onTriggered: panel.queueGitBackground()
  }
  Connections {
    target: panel.root
    function onOpenedChanged() {
      if (panel.root.opened)
        panel.scheduleGitBackground()
    }
  }
  // One suggestion shared by selected-project surface consumers.
  readonly property var agentChoice: {
    var agents = root.projectClient.snapshot.agents || {}, project = projectsPage.selectedProject
    return Suggestion.suggest(agents.tools || [], agents.usage || {}, project && project.tools ? project.tools.agentId || null : null, nowMs)
  }
  Timer {
    interval: 60000
    repeat: true
    running: panel.visible
    onTriggered: panel.nowMs = Date.now()
  }
  // Narrow widths use a compact selector instead of the tall sidebar.
  readonly property bool compact: width < Style.space(720)
  // Reduce window chrome on short logical screens.
  readonly property bool shortScreen: height < Style.space(400)
  // Current project destination, retained independently of window visibility.
  property string section: 'overview'
  // Opaque request identities stay one explicit step below daily recovery actions.
  property bool requestDetailsExpanded: false
  // Overview and Agents reuse one activity observation lifetime.
  readonly property bool activityVisible: (section === 'agents' || section === 'overview') && !projectsPage.setupActive && !!projectsPage.selectedProject
  // Exact-checkout summaries reuse shared snapshots; never own process lifetimes.
  readonly property var overviewModel: Overview.overview(projectsPage.selectedProject, root.gitClient.checkoutId, root.gitClient.current, root.actionClient.snapshot, root.activityClient.snapshot, root.projectClient.snapshot, Math.max(nowMs, Date.now()))
  Binding {
    target: projectsPage.details
    property: 'actionClient'
    value: panel.root.actionClient
  }
  // Refresh is observation only and every effect checks the inert boundary.
  function refreshOverview() {
    if (root.inert)
      return
    root.gitClient.refresh()
    root.actionClient.refresh()
    root.actionClient.checkAvailability()
    root.actionClient.observeSummary()
    root.activityClient.refresh()
  }
  // Revalidate authoritative identity when a compact control is activated.
  function overviewAction(method, target) {
    var client = root.actionClient
    if (root.inert || client.pending || !target || target.projectId !== client.projectId || target.checkoutId !== client.checkoutId)
      return
    var row = overviewModel.services.concat(overviewModel.checks).find(function (r) {
      return JSON.stringify(r.target) === JSON.stringify(target)
    })
    if (!row || !row.controls.some(function (c) {
      return c.method === method
    }))
      return
    if (method === 'start') {
      if (client.availability.execution && !client.submissionUncertain)
        client.start(target.actionId, target.revision)
    } else if (method === 'stop')
      client.stop(target.runId)
    else if (method === 'logs') {
      if (chooseSection('actions'))
        client.logs(target.runId)
    } else if (method === 'open-preview') {
      var run = (client.snapshot.runs || []).find(function (r) {
        return r.id === target.runId && r.projectId === target.projectId && r.checkoutId === target.checkoutId
      })
      if (run) {
        client.publishRun(run)
        client.openPreview(target.runId)
      }
    }
  }
  // Detail navigation selects the retained task/run without executing commands.
  function overviewDetails(section, target) {
    if (!chooseSection(section))
      return
    if (section === 'agents' && target.taskId)
      agentsView.inspectTask(target.taskId)
    if (section === 'actions' && target.actionId) {
      projectsPage.details.actions.selectAction(target.actionId, target.revision)
      if (!root.inert && target.runId)
        root.actionClient.observeRun(target.runId)
    }
  }
  // Latest geometry/content change disarms stale pointer activation.
  property real layoutChangedAt: 0
  // Unsaved drafts, wizard state and pending work prevent changing selection.
  readonly property bool navigationBlocked: projectsPage.setupActive || projectsPage.setupNavigationPending || root.activityClient.pending
  // Draft decisions are independent of accepted operation serialization.
  readonly property bool hasUnsavedDraft: projectsPage.details.dirty || projectsPage.details.actions.editing || projectsPage.details.profileEditing
  // Only explicit Save intent can continue after authoritative draft acknowledgement.
  property bool savingNavigationDraft: false
  // Retain the exact requested destination while asking for a draft decision.
  function guardDraft(target) {
    if (!hasUnsavedDraft)
      return false
    draftGuard.pendingTarget = target
    savingNavigationDraft = false
    draftGuard.open()
    return true
  }
  // Route the retained destination through the same ordinary navigation guards.
  function continueDraftNavigation() {
    var target = draftGuard.pendingTarget
    savingNavigationDraft = false
    draftGuard.pendingTarget = null
    draftGuard.close()
    if (!target)
      return
    if (target.profileList) {
      projectsPage.details.profileAdding = false
      section = 'profiles'
      scrollTo(0)
    } else if (target.setup)
      projectsPage.startSetup()
    else if (target.projectId !== root.projectId)
      navigate(target.projectId)
    else
      chooseSection(target.section)
  }
  // Add project is a destination too; editing never silently disables it.
  function addProject() {
    if (navigationBlocked || root.inert || guardDraft({
      setup: true
    }))
      return
    projectsPage.startSetup()
  }
  // Save each retained draft through its existing validation and transport.
  function saveNavigationDraft() {
    if (root.inert || draftGuard.pending || !draftGuard.pendingTarget)
      return
    savingNavigationDraft = true
    if (projectsPage.details.dirty)
      projectsPage.details.applyDraft()
    else if (projectsPage.details.profileEditing)
      projectsPage.details.profileEditor.save()
    else if (projectsPage.details.actions.editing)
      projectsPage.details.actions.editor.save()
    Qt.callLater(panel.finishNavigationSave)
  }
  // Authoritative success clears the draft; failed or newer edits keep it visible.
  function finishNavigationSave() {
    if (savingNavigationDraft && !hasUnsavedDraft && !projectsPage.setupNavigationPending)
      continueDraftNavigation()
  }
  onHasUnsavedDraftChanged: Qt.callLater(panel.finishNavigationSave)
  onNavigationBlockedChanged: Qt.callLater(panel.finishNavigationSave)
  ProjectDraftGuard {
    id: draftGuard
    parent: panel
    pending: projectsPage.setupNavigationPending || panel.root.activityClient.pending
    error: (projectsPage.details.profileEditing ? projectsPage.details.profileEditor.fieldError : '') || projectsPage.details.fieldError || projectsPage.error || (panel.root.actionClient.error ? panel.root.actionClient.error.message : '') || projectsPage.details.actions.editor.fieldError
    pointerGate: pointerGate
    onSaveRequested: panel.saveNavigationDraft()
    onDiscardRequested: {
      if (pending || panel.root.inert)
        return
      projectsPage.details.discardDraft()
      projectsPage.details.actions.editing = false
      projectsPage.details.profileEditing = false
      projectsPage.details.profileEditor.fieldError = ''
      projectsPage.details.submittedProfileDraft = null
      panel.continueDraftNavigation()
    }
    onKeepEditingRequested: {
      if (pending || panel.root.inert)
        return
      panel.savingNavigationDraft = false
      pendingTarget = null
      close()
    }
  }
  // Select a known project only when no draft or operation would be hidden.
  function navigate(id) {
    if (id !== '' && !(root.projectController.state.projects || []).some(function (p) {
      return p.id === id
    }))
      return false
    if (id === root.projectId)
      return true
    if (navigationBlocked)
      return false
    if (root.inert || guardDraft({
      projectId: id,
      section: 'overview'
    }))
      return false
    root.projectId = id
    root.flushNavigation()
    section = 'overview'
    scrollTo(0)
    stampLayout()
    return true
  }
  // Ctrl+K is deliberate navigation and does not consume ordinary field text.
  function focusProjectSearch() {
    if (navigationBlocked || root.inert)
      return
    if (compact)
      projectPicker.open()
    else
      sidebar.focusSearch()
  }
  // Layer windows do not match Qt's active-window shortcut context.
  // The opened overlay owns exclusive keyboard focus; hidden Projects claims no keys.
  Shortcut {
    sequence: 'Ctrl+K'
    context: Qt.ApplicationShortcut
    enabled: panel.root.opened && panel.visible && !panel.root.inert && !panel.navigationBlocked
    onActivated: panel.focusProjectSearch()
  }
  ProjectPicker {
    id: projectPicker
    objectName: 'projectPicker'
    parent: panel
    rows: Navigation.rows(panel.root.projectController.state.projects || [], panel.root.projectController.state.navigation || {}, query, frozenIds, panel.root.gitClient.cache)
    rowsFiltered: true
    selectedId: panel.root.projectId
    displayOnly: panel.root.inert || panel.navigationBlocked
    pointerGate: pointerGate
    pinningEnabled: true
    showAddProject: true
    onSetupRequested: panel.addProject()
    onSelected: function (id) {
      panel.navigate(id)
    }
    onPinRequested: function (id, pinned) {
      panel.root.rememberNavigation(id, pinned)
    }
  }
  onCompactChanged: projectPicker.close()
  onVisibleChanged: {
    if (!visible) {
      projectPicker.close()
      draftGuard.close()
      draftGuard.pendingTarget = null
      savingNavigationDraft = false
    } else
      scheduleGitBackground()
  }
  // Choose a supported destination after checking draft and pending guards.
  function chooseSection(next) {
    if (['overview', 'actions', 'agents', 'preferences', 'profiles', 'help'].indexOf(next) < 0)
      return false
    if (next !== section && (navigationBlocked || root.inert || guardDraft({
        projectId: root.projectId,
        section: next
      })))
      return false
    section = next
    if (next === 'agents')
      Qt.callLater(function () {
        agentsView.focusTasks()
      })
    scrollTo(0)
    return true
  }
  // Refuse capture while action acceptance or activity work is pending.
  function captureBusy() {
    return projectsPage.details.actions.pending || root.activityClient.pending
  }
  // Remember the real keyboard target when a backing window exists.
  function captureFocus() {
    return panel.Window.window ? panel.Window.window.activeFocusItem : null
  }
  // Serialize local presentation and observations without backend reads.
  function captureSnapshot() {
    return {
      agents: agentsView.captureSnapshot(),
      contentY: scroller.contentY,
      section: section,
      query: sidebar.query,
      sidebarContentY: sidebar.contentY,
      draftTarget: draftGuard.pendingTarget,
      draftGuardOpen: draftGuard.opened,
      projects: projectsPage.captureSnapshot()
    }
  }
  // Restore only capture-owned state and retained drafts by exact identity.
  function captureRestore(saved) {
    agentsView.captureRestore(saved.agents || {})
    section = saved.section || 'overview'
    sidebar.query = saved.query || ''
    sidebar.restoreViewport(saved.sidebarContentY || 0)
    projectsPage.captureRestore(saved.projects)
    draftGuard.pendingTarget = saved.draftTarget || null
    if (saved.draftGuardOpen && draftGuard.pendingTarget)
      draftGuard.open()
    Qt.callLater(function () {
      panel.scrollTo(saved.contentY || 0)
    })
  }
  // Initialize inert fixture presentation without invoking an owner operation.
  function captureReset(fixture) {
    draftGuard.close()
    draftGuard.pendingTarget = null
    savingNavigationDraft = false
    section = fixture && fixture.projectSection || 'overview'
    sidebar.query = ''
    agentsView.captureRestore({})
    projectsPage.captureReset(fixture)
    scrollTo(0)
  }
  // Wait for settled production geometry before capturing artwork.
  function captureReady() {
    return Date.now() - layoutChangedAt >= 250
  }
  // Focus a predictable keyboard target when the window is summoned.
  function focusKeys() {
    closeButton.forceActiveFocus()
  }
  // Invalidate pointer movement accepted before content moved.
  function stampLayout() {
    layoutChangedAt = Date.now()
    pointerGate.reset()
  }
  // Clamp explicit scroll requests inside the current content viewport.
  function scrollTo(y) {
    scroller.cancelFlick()
    scroller.contentY = Math.max(0, Math.min(y, Math.max(0, scroller.contentHeight - scroller.height)))
  }
  // Expose the complete keyboard-focused control inside the scroll viewport.
  function revealFocus(item) {
    if (!item)
      return
    var ancestor = item.parent
    while (ancestor && ancestor !== scroller.contentItem)
      ancestor = ancestor.parent
    if (!ancestor)
      return
    var position = item.mapToItem(scroller.contentItem, 0, 0)
    if (position.y < scroller.contentY)
      scrollTo(position.y)
    else if (position.y + item.height > scroller.contentY + scroller.height)
      scrollTo(position.y + item.height - scroller.height)
  }
  onWidthChanged: stampLayout()
  onHeightChanged: stampLayout()
  onSectionChanged: stampLayout()
  Connections {
    target: panel.Window.window
    function onActiveFocusItemChanged() {
      panel.revealFocus(panel.Window.window.activeFocusItem)
    }
  }
  // Only explicit registration seeds presets, serialized after any metadata write.
  property var presetInFlight: null
  // Drain optional setup only through the registry mutation serialization boundary.
  function flushProfilePresets() {
    var client = root.projectController
    if (root.inert || client.pending || client.reading || presetInFlight || !projectsPage.profilePresetQueue.length)
      return
    var args = projectsPage.profilePresetQueue[0]
    projectsPage.profilePresetQueue = projectsPage.profilePresetQueue.slice(1)
    if (!(client.state.projects || []).some(function (p) {
      return p.id === args.projectId
    })) {
      Qt.callLater(panel.flushProfilePresets)
      return
    }
    presetInFlight = args
    if (!client.request('profile-save', args)) {
      presetInFlight = null
      projectsPage.profilePresetQueue = []
      projectsPage.profileSetupError = 'Project added. Open Manage profiles to choose and save your tools.'
    }
  }
  Connections {
    target: projectsPage
    function onProfilePresetQueueChanged() {
      Qt.callLater(panel.flushProfilePresets)
    }
  }
  Connections {
    target: panel.root.projectController
    function onStateChanged() {
      panel.stampLayout()
      panel.scheduleGitBackground()
    }
    function onToolsChanged() {
      panel.stampLayout()
    }
    function onMutationCompleted(action, args, state) {
      projectsPage.registryMutationCompleted(action, args, state)
      if (action === 'profile-save' && panel.presetInFlight && JSON.stringify(panel.presetInFlight) === JSON.stringify(args))
        panel.presetInFlight = null
      Qt.callLater(panel.flushProfilePresets)
    }
    function onErrorChanged() {
      if (panel.presetInFlight && panel.root.projectController.error) {
        panel.presetInFlight = null
        projectsPage.profilePresetQueue = []
        projectsPage.profileSetupError = 'Project added, but profiles could not be saved. Open Manage profiles to choose your tools. ' + panel.root.projectController.error
      }
    }
    function onPendingChanged() {
      Qt.callLater(panel.flushProfilePresets)
    }
    function onReadingChanged() {
      Qt.callLater(panel.flushProfilePresets)
    }
  }
  Connections {
    target: panel.root.discoveryClient
    function onCandidatesChanged() {
      panel.stampLayout()
    }
    function onPendingChanged() {
      panel.stampLayout()
    }
  }
  Connections {
    target: panel.root.projectClient
    function onSnapshotChanged() {
      panel.stampLayout()
    }
    function onOperationChanged(operation) {
      panel.stampLayout()
    }
  }
  PointerMoveGate {
    id: pointerGate
    referenceItem: card
    property real layoutChangedAt: panel.layoutChangedAt
  }
  Aranea.SurfaceCard {
    id: card
    anchors.fill: parent
    contentPadding: Style.space(16)
    fillColor: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.98)
    borderSpecOverride: Border.flat(Util.alpha(Color.foreground, 0.16), 1)
    FocusScope {
      anchors.fill: parent
      anchors.margins: Style.space(panel.shortScreen ? 12 : 16)
      focus: true
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) {
          panel.root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
          panel.scrollTo(scroller.contentY + (event.key === Qt.Key_PageDown ? 1 : -1) * scroller.height * 0.9)
          event.accepted = true
        }
      }
      ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(16)
        RowLayout {
          Layout.fillWidth: true
          Aranea.ActionButton {
            objectName: 'chooseProject'
            visible: panel.compact && !projectsPage.selectedProject && !projectsPage.setupActive
            text: 'Choose project'
            enabled: !panel.root.inert && !panel.navigationBlocked
            pointerGate: pointerGate
            onClicked: projectPicker.open()
          }
          Aranea.UiLabel {
            Layout.fillWidth: true
            text: 'Projects'
            font.pixelSize: Style.font.heading
            font.bold: true
          }
          Aranea.ActionButton {
            id: closeButton
            text: 'Close'
            variant: 'quiet'
            pointerGate: pointerGate
            onClicked: panel.root.close()
          }
        }
        GridLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          columns: panel.compact || projectsPage.setupActive ? 1 : 2
          columnSpacing: Style.space(16)
          rowSpacing: Style.space(8)
          Rectangle {
            visible: !projectsPage.setupActive && !panel.compact
            Layout.fillWidth: panel.compact
            Layout.preferredWidth: panel.compact ? -1 : Style.space(260)
            Layout.fillHeight: !panel.compact
            implicitHeight: panel.compact ? sidebar.implicitHeight + Style.space(24) : 0
            radius: Style.space(6)
            color: Util.alpha(Aranea.DesignTokens.accent, 0.04)
            border.color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
            border.width: 1
            ProjectsSidebar {
              id: sidebar
              anchors.fill: parent
              anchors.margins: Style.space(12)
              compact: panel.compact
              projects: panel.root.projectController.state.projects || []
              gitCache: panel.root.gitClient.cache
              navigation: panel.root.projectController.state.navigation || {}
              bindings: panel.root.projectClient.snapshot.bindings || []
              selectedId: projectsPage.selectedProject ? projectsPage.selectedProject.id : panel.root.projectId
              navigationEnabled: !panel.navigationBlocked && !panel.root.inert
              pointerGate: pointerGate
              onProjectRequested: function (id) {
                panel.navigate(id)
              }
              onPinRequested: function (id, pinned) {
                panel.root.rememberNavigation(id, pinned)
              }
              onSetupRequested: panel.addProject()
              onViewportChanged: {
                panel.stampLayout()
                panel.scheduleGitBackground()
              }
              onFilteredProjectsChanged: panel.scheduleGitBackground()
              onHeightChanged: panel.scheduleGitBackground()
            }
          }
          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Flickable {
              id: scroller
              objectName: 'projectsContentViewport'
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              contentWidth: Math.max(1, width - Style.space(16))
              contentHeight: content.implicitHeight
              boundsBehavior: Flickable.StopAtBounds
              onContentYChanged: panel.stampLayout()
              onContentHeightChanged: panel.stampLayout()
              ScrollBar.vertical: ScrollBar {
                objectName: 'settingsScrollBar'
                parent: scroller
                anchors.right: scroller.right
                anchors.top: scroller.top
                anchors.bottom: scroller.bottom
                width: Style.space(14)
                active: scroller.contentHeight > scroller.height + 1
                policy: scroller.contentHeight > scroller.height + 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                interactive: true
                minimumSize: 0.08
                contentItem: Rectangle {
                  implicitWidth: Style.space(6)
                  implicitHeight: Style.space(28)
                  radius: width / 2
                  color: Util.alpha(Color.foreground, 0.5)
                }
                background: Rectangle {
                  color: 'transparent'
                }
              }
              Column {
                id: content
                width: scroller.contentWidth
                spacing: Style.space(16)
                ProjectHeader {
                  width: content.width
                  visible: !!projectsPage.selectedProject && !projectsPage.setupActive
                  compact: panel.compact
                  managementActive: panel.section === 'profiles'
                  navigationEnabled: !panel.navigationBlocked
                  onProjectPickerRequested: projectPicker.open()
                  onCheckoutRequested: function (id, checkoutId) {
                    panel.root.clearDismissalIntent()
                    panel.root.projectController.request('select-checkout', {
                      projectId: id,
                      checkoutId: checkoutId
                    })
                  }
                  project: projectsPage.selectedProject
                  git: panel.overviewModel.git
                  gitStale: !!panel.root.gitClient.error || !!git && panel.nowMs - git.observedAt > 30000
                  openAvailable: panel.root.projectClient.available && !!panel.root.projectClient.snapshot.availability && panel.root.projectClient.snapshot.availability.compositor === true
                  pending: panel.root.projectClient.submitting
                  acceptanceUnknown: panel.root.projectClient.acceptanceUnknown
                  displayOnly: !!panel.root.inert
                  pointerGate: pointerGate
                  tools: panel.root.projectController.tools
                  menuHost: panel
                  onStartProfile: function (id, revision) {
                    panel.root.startProfile(id, revision, false)
                  }
                  onManageProfilesRequested: panel.chooseSection('profiles')
                }
                Aranea.PageHeader {
                  width: content.width
                  visible: projectsPage.setupActive
                  title: 'Add a project'
                  description: 'Add an exact Git repository to open its Overview.'
                }
                Flow {
                  width: content.width
                  spacing: Style.space(4)
                  visible: !projectsPage.setupActive && (!!projectsPage.selectedProject || panel.section === 'help' || panel.section === 'preferences')
                  Repeater {
                    model: [
                      {
                        id: 'overview',
                        label: 'Overview'
                      },
                      {
                        id: 'actions',
                        label: 'Actions'
                      },
                      {
                        id: 'agents',
                        label: 'Agents'
                      },
                      {
                        id: 'preferences',
                        label: 'Preferences'
                      },
                      {
                        id: 'help',
                        label: 'Help'
                      }
                    ]
                    Aranea.ActionButton {
                      required property var modelData
                      objectName: 'projectTab:' + modelData.id
                      text: modelData.label
                      selected: panel.section === modelData.id
                      enabled: (modelData.id === 'help' || modelData.id === 'preferences' || !!projectsPage.selectedProject) && (panel.section === modelData.id || !panel.navigationBlocked)
                      pointerGate: pointerGate
                      onClicked: panel.chooseSection(modelData.id)
                    }
                  }
                }
                Aranea.UiLabel {
                  width: content.width
                  visible: !!projectsPage.profileSetupError
                  text: projectsPage.profileSetupError
                  color: Aranea.DesignTokens.attention
                }
                ProjectsWelcome {
                  width: content.width
                  visible: !projectsPage.selectedProject && !projectsPage.setupActive && panel.section !== 'help' && panel.section !== 'preferences'
                  hasProjects: (panel.root.projectController.state.projects || []).length > 0
                  pending: panel.navigationBlocked
                  displayOnly: !!panel.root.inert
                  pointerGate: pointerGate
                  onSetupRequested: panel.addProject()
                  onHelpRequested: panel.chooseSection('help')
                }
                Aranea.PageHeader {
                  width: content.width
                  visible: panel.section === 'preferences' && !projectsPage.setupActive
                  title: 'Preferences'
                  description: 'Choose tools and workspace behavior. Manage the folders used to discover repositories.'
                }
                ProjectsPage {
                  id: projectsPage
                  objectName: 'projectsPage'
                  width: scroller.contentWidth
                  sidebarNavigation: true
                  viewSection: panel.section
                  registryState: panel.root.projectController.state
                  tools: panel.root.projectController.tools
                  agentChoice: panel.agentChoice
                  discoveryClient: panel.root.discoveryClient
                  projectClient: panel.root.projectClient
                  projectId: panel.root.projectId
                  displayOnly: !!panel.root.inert
                  metadataPending: panel.root.navigationSaving
                  pending: panel.root.projectController.pending || panel.root.projectController.reading
                  error: panel.root.projectController.error || panel.root.projectClient.error
                  pointerGate: pointerGate
                  onRegisterRequested: function (paths) {
                    panel.root.projectController.request('register', {
                      paths: paths
                    })
                  }
                  onRootAddRequested: function (path) {
                    panel.root.projectController.request('root-add', {
                      path: path
                    })
                  }
                  onRootRemoveRequested: function (id) {
                    panel.root.projectController.request('root-remove', {
                      rootId: id
                    })
                  }
                  onDiscoverRequested: function (id) {
                    panel.root.discoveryClient.start(id)
                  }
                  onCancelRequested: panel.root.discoveryClient.cancel()
                  onIgnoreRequested: function (path) {
                    panel.root.projectController.request('ignore', {
                      path: path
                    })
                  }
                  onUnignoreRequested: function (path) {
                    panel.root.projectController.request('unignore', {
                      path: path
                    })
                  }
                  onProfileListRequested: {
                    if (!panel.root.inert && !panel.navigationBlocked)
                      panel.guardDraft({
                        projectId: panel.root.projectId,
                        section: 'profiles',
                        profileList: true
                      })
                  }
                  onProfileSaveRequested: function (id, profile, revision) {
                    var args = {
                      projectId: id,
                      profile: profile
                    }
                    if (revision > 0)
                      args.expectedProfileRevision = revision
                    panel.root.projectController.request('profile-save', args)
                  }
                  onProfileRemoveRequested: function (id, profileId, revision) {
                    panel.root.projectController.request('profile-remove', {
                      projectId: id,
                      profileId: profileId,
                      expectedProfileRevision: revision
                    })
                  }
                  onConfigureRequested: function (id, draft) {
                    panel.root.projectController.request('configure', Object.assign({
                      projectId: id
                    }, draft))
                  }
                  onCheckoutRequested: function (id, checkout) {
                    panel.root.projectController.request('select-checkout', {
                      projectId: id,
                      checkoutId: checkout
                    })
                  }
                  onLocateRequested: function (id, checkout, path) {
                    panel.root.projectController.request('relocate', {
                      projectId: id,
                      checkoutId: checkout,
                      path: path
                    })
                  }
                  onRemoveRequested: function (id) {
                    panel.root.projectController.request('remove', {
                      projectId: id
                    })
                  }
                  onOpenRequested: function (payload) {
                    panel.root.projectClient.request(payload)
                  }
                  onDetailsRequested: function (id) {
                    if (projectsPage.exactSetup && !projectsPage.setupActive)
                      panel.chooseSection('overview')
                    panel.navigate(id)
                  }
                  onRefreshRequested: {
                    panel.root.projectController.refresh()
                    panel.root.projectClient.refresh()
                    panel.root.gitClient.refresh()
                  }
                }
                ColumnLayout {
                  width: content.width
                  visible: !!projectsPage.selectedProject && (panel.root.projectClient.acceptanceUnknown || !!panel.root.projectClient.requestError || panel.root.projectClient.preparing)
                  Aranea.UiLabel {
                    Layout.fillWidth: true
                    text: panel.root.projectClient.acceptanceUnknown ? 'Launch acceptance is unknown. The earlier request may still finish.' : panel.root.projectClient.preparing ? 'Preparing this profile…' : panel.root.projectClient.requestError ? panel.root.projectClient.requestError.message : ''
                    color: Aranea.DesignTokens.attention
                  }
                  Flow {
                    Layout.fillWidth: true
                    spacing: Style.space(8)
                    Aranea.ActionButton {
                      text: 'Cancel preparation'
                      visible: panel.root.projectClient.canCancelPreparation
                      enabled: !panel.root.inert
                      pointerGate: pointerGate
                      onClicked: panel.root.cancelPreparation()
                    }
                    Aranea.ActionButton {
                      text: 'Check launch status'
                      visible: panel.root.projectClient.acceptanceUnknown
                      enabled: !panel.root.inert && !panel.root.projectClient.submitting
                      pointerGate: pointerGate
                      onClicked: panel.root.projectClient.checkEnvironmentActivation()
                    }
                    Aranea.ActionButton {
                      text: 'Start another environment'
                      visible: panel.root.projectClient.acceptanceUnknown
                      enabled: !panel.root.inert && !panel.root.projectClient.submitting && !!Profiles.remembered(projectsPage.selectedProject)
                      pointerGate: pointerGate
                      onClicked: {
                        var profile = Profiles.remembered(projectsPage.selectedProject)
                        if (profile)
                          panel.root.startProfile(profile.id, profile.revision, true)
                      }
                    }
                    Aranea.ActionButton {
                      text: panel.requestDetailsExpanded ? 'Hide request details' : 'Request details'
                      visible: panel.root.projectClient.acceptanceUnknown
                      variant: 'quiet'
                      pointerGate: pointerGate
                      onClicked: panel.requestDetailsExpanded = !panel.requestDetailsExpanded
                    }
                    Aranea.ActionButton {
                      text: 'Manage profiles'
                      visible: !panel.root.projectClient.acceptanceUnknown && !panel.root.projectClient.preparing
                      pointerGate: pointerGate
                      onClicked: panel.chooseSection('profiles')
                    }
                  }
                  Aranea.UiLabel {
                    Layout.fillWidth: true
                    visible: panel.requestDetailsExpanded && panel.root.projectClient.acceptanceUnknown
                    text: 'Request: ' + panel.root.projectClient.activationId + '\nEarlier unresolved requests: ' + panel.root.projectClient.unresolvedEnvironmentActivations.length
                    technical: true
                  }
                }
                ProjectOverview {
                  width: scroller.contentWidth
                  visible: panel.section === 'overview' && !!projectsPage.selectedProject && !projectsPage.setupActive
                  model: panel.overviewModel
                  gitError: panel.root.gitClient.error
                  gitLoading: panel.root.gitClient.loading
                  nowMs: panel.nowMs
                  displayOnly: panel.root.inert
                  actionPending: panel.root.actionClient.pending || panel.root.actionClient.submissionUncertain
                  agentPending: panel.root.activityClient.pending
                  workspacePending: panel.root.projectClient.submitting || panel.root.projectClient.acceptanceUnknown || !projectsPage.details.openAvailable
                  executionAvailable: panel.root.actionClient.availability.execution === true
                  actionError: panel.root.actionClient.submissionUncertain ? 'Submission unconfirmed. Refresh actions in Details to recover the receipt.' : panel.root.actionClient.error ? panel.root.actionClient.error.message + ' Manage actions to recover.' : panel.root.actionClient.summaryError ? panel.root.actionClient.summaryError.message : panel.root.actionClient.available && panel.overviewModel.services.concat(panel.overviewModel.checks).length && panel.root.actionClient.availability.execution !== true ? 'Execution unavailable. Manage actions to check required helpers.' : ''
                  activityError: panel.root.activityClient.error ? 'Agent connection unavailable. Open Details to reconnect.' : ''
                  pointerGate: pointerGate
                  onRefreshRequested: panel.refreshOverview()
                  onActionRequested: function (method, target) {
                    panel.overviewAction(method, target)
                  }
                  onAgentRequested: function (method, taskId) {
                    if (!panel.root.inert && panel.overviewModel.agents.some(function (r) {
                      return r.target.taskId === taskId && r.controls.some(function (c) {
                        return c.method === method
                      })
                    }))
                      agentsView.submit(method, taskId)
                  }
                  onWorkspaceRequested: function (method, target) {
                    if (panel.root.inert || panel.root.projectClient.submitting || !panel.overviewModel.workspaces.some(function (r) {
                      return JSON.stringify(r.target) === JSON.stringify(target) && r.controls.some(function (c) {
                        return c.method === method
                      })
                    }))
                      return
                    if (method === 'return')
                      panel.root.returnEnvironment(target)
                    else if (method === 'open')
                      panel.root.projectClient.request(target)
                    else {
                      var parts = method.split(':'), payload = Object.assign({}, target)
                      payload[parts[0] + 'Role'] = parts[1]
                      panel.root.clearDismissalIntent()
                      panel.root.projectClient.recoverEnvironment(payload)
                    }
                  }
                  onDetailsRequested: function (section, target) {
                    panel.overviewDetails(section, target)
                  }
                }
                ProjectAgents {
                  id: agentsView
                  objectName: 'projectAgents'
                  width: scroller.contentWidth
                  visible: panel.section === 'agents' && !!projectsPage.selectedProject && !projectsPage.setupActive
                  project: projectsPage.selectedProject
                  registry: panel.root.projectController.state
                  client: panel.root.activityClient
                  agentChoice: panel.agentChoice
                  pending: projectsPage.details.pending
                  openAvailable: projectsPage.details.openAvailable
                  pointerGate: pointerGate
                  onStartRequested: function (agentId) {
                    if (panel.chooseSection('overview'))
                      projectsPage.details.startAgent(agentId)
                  }
                  displayOnly: !!panel.root.inert
                  maxHeight: Math.max(Style.space(200), scroller.height)
                  onSetupRequested: panel.chooseSection('help')
                }
                Aranea.WorkflowHelp {
                  width: scroller.contentWidth
                  visible: panel.section === 'help' && !projectsPage.setupActive
                  topic: 'projects'
                }
                Aranea.WorkflowHelp {
                  width: scroller.contentWidth
                  visible: panel.section === 'help' && !projectsPage.setupActive
                  topic: 'actions'
                }
                Aranea.WorkflowHelp {
                  width: scroller.contentWidth
                  visible: panel.section === 'help' && !projectsPage.setupActive
                  topic: 'agents'
                }
              }
            }
          }
        }
        Aranea.UiLabel {
          Layout.fillWidth: true
          visible: !panel.shortScreen
          text: projectsPage.setupActive ? (projectsPage.exactSetup ? 'Choose a repository to add it to Projects.' : 'Complete or exit setup before switching projects.') : panel.navigationBlocked ? 'Waiting for the current operation.' : panel.root.captureSaved ? 'Preview · read-only' : 'Tab navigate · Page Up/Down scroll · Esc close'
          opacity: 0.5
        }
      }
    }
  }
}
