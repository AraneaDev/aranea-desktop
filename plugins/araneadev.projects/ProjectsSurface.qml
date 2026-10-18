// Standalone project workspace with persistent drafts and responsive navigation.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "AgentSuggestion.js" as Suggestion
import "ProjectsNavigation.js" as Navigation
import "ProjectOverview.js" as Overview
import "ProjectActionRecords.js" as Records
import "ProjectActionSuggestions.js" as Suggestions
import "ProjectProfiles.js" as Profiles
import "ProjectProblems.js" as Problems
import "ProjectReview.js" as Review
import "ProjectsLogic.js" as Logic

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
  // Overview and Agents reuse one activity observation lifetime.
  readonly property bool activityVisible: (section === 'agents' || section === 'overview') && !projectsPage.setupActive && !!projectsPage.selectedProject
  // Exact-checkout summaries reuse shared snapshots; never own process lifetimes.
  readonly property var overviewModel: Overview.overview(projectsPage.selectedProject, root.gitClient.checkoutId, root.gitClient.current, root.actionClient.snapshot, root.activityClient.snapshot, root.projectClient.snapshot, Math.max(nowMs, Date.now()))
  // Saved definitions of the selected project, live from the shared client.
  readonly property var selectedDefinitions: projectsPage.selectedProject ? Records.definitions(root.actionClient.snapshot, projectsPage.selectedProject.id) : []
  // Overview wants detected commands only while the project has no saved actions.
  readonly property bool overviewWantsSuggestions: section === 'overview' && !!projectsPage.selectedProject && !projectsPage.setupActive && !root.inert && selectedDefinitions.length === 0
  // Up to three unsaved detected commands for the empty Overview.
  readonly property var overviewSuggestions: overviewWantsSuggestions && root.actionClient.suggestionsReady ? Suggestions.overviewPicks(Suggestions.pending(root.actionClient.detection, selectedDefinitions)) : []
  onOverviewWantsSuggestionsChanged: if (overviewWantsSuggestions)
    root.actionClient.detect(false)
  // Re-detect once a project or checkout switch has settled both identities.
  function redetectOverview() {
    if (overviewWantsSuggestions)
      root.actionClient.detect(false)
  }
  Connections {
    target: panel.root.projectController
    function onMutationFailed(action, args, message) {
      if (action === 'review-mark')
        panel.reviewActionError = {
          projectId: args.projectId,
          checkoutId: args.checkoutId,
          error: {
            code: 'REGISTRY_WRITE_FAILED',
            message: message,
            recovery: ''
          }
        }
    }
  }
  Connections {
    target: panel.root.actionClient
    function onProjectIdChanged() {
      Qt.callLater(panel.redetectOverview)
    }
    function onCheckoutIdChanged() {
      Qt.callLater(panel.redetectOverview)
    }
  }
  // Save one detected command the Overview still shows; Run stays separate.
  function addOverviewSuggestion(key) {
    if (root.inert)
      return
    var row = overviewSuggestions.find(function (r) {
      return r.key === key
    })
    if (row)
      root.actionClient.addSuggestions([row.definition])
  }
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
    if (overviewWantsSuggestions)
      root.actionClient.detect(true)
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
    } else if (target.checkoutId)
      inspectCheckout(target.projectId, target.checkoutId)
    else if (target.setup)
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
  function inspectCheckout(id, checkoutId) {
    var project = (root.projectController.state.projects || []).find(function (row) {
      return row.id === id
    })
    if (root.inert || navigationBlocked || !project || !(project.checkouts || []).some(function (checkout) {
      return checkout.id === checkoutId
    }))
      return false
    if ((id !== root.projectId || checkoutId !== root.selectedCheckoutId || section !== 'overview') && guardDraft({
      projectId: id,
      checkoutId: checkoutId,
      section: 'overview'
    }))
      return false
    root.projectId = id
    root.inspectionCheckoutId = checkoutId
    section = 'overview'
    scrollTo(0)
    stampLayout()
    return true
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
    return selectProject(id)
  }
  // Make a known project the selection, recording the visit.
  function selectProject(id) {
    root.projectId = id
    root.flushNavigation()
    section = 'overview'
    scrollTo(0)
    stampLayout()
    return true
  }
  // The compact quick switcher replaces the full layout while this mode is set.
  readonly property bool switcherMode: root.mode === 'switcher'
  // The switcher never hides a setup wizard or an unsaved draft; a running operation does not stop it.
  readonly property bool switcherBlocked: projectsPage.setupActive || hasUnsavedDraft
  // Registry, discovery, action or activity work that navigation also waits for; a watched start is not one.
  readonly property bool switcherPending: (root.projectController.pending || root.projectController.reading) && !root.navigationSaving || root.discoveryClient.pending || projectsPage.details.actions.pending || root.activityClient.pending
  // Select a known project for the switcher; an operation that is only being watched does not block this.
  function switcherSelect(id) {
    if (!(root.projectController.state.projects || []).some(function (p) {
      return p.id === id
    }))
      return false
    if (root.inert || switcherPending)
      return false
    if (id === root.projectId)
      return true
    if (switcherBlocked)
      return false
    return selectProject(id)
  }
  // Enter on a switcher row: select its project first, then use the ordinary start or return path.
  function switcherGo(row) {
    if (row && row.action.kind === 'review')
      return switcherReview(row)
    if (root.inert || !root.opened || !row || switcher.busy || !switcherSelect(row.id))
      return false
    if (row.action.kind === 'return')
      return root.returnEnvironment(row.action.target)
    if (row.action.kind === 'start')
      return root.startProfile(row.action.target.profileId, row.action.target.profileRevision, false)
    return false
  }
  // Enter on a review row: open Projects on that task checkout's Overview; nothing launches.
  function switcherReview(row) {
    if (root.inert || !root.opened || !row || switcher.busy || !switcherSelect(row.id))
      return false
    var target = row.action.target
    root.mode = ''
    section = 'overview'
    var project = (root.projectController.state.projects || []).find(function (p) {
      return p.id === row.id
    })
    if (project && project.lastCheckoutId !== target.checkoutId)
      root.projectController.request('select-checkout', {
        projectId: target.projectId,
        checkoutId: target.checkoutId
      })
    Qt.callLater(focusKeys)
    return true
  }
  // The explicit Start after a failed return uses the row's remembered profile.
  function switcherStart(row) {
    if (root.inert || !root.opened || !row || !row.startTarget || switcher.busy || !switcherSelect(row.id))
      return false
    return root.startProfile(row.startTarget.profileId, row.startTarget.profileRevision, false)
  }
  // Open the full layout on a project, or on setup when no project is given.
  function switcherExpand(id) {
    if (root.inert)
      return
    if (id && !switcherSelect(id))
      return
    root.mode = ''
    if (!id)
      addProject()
    Qt.callLater(focusKeys)
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
    enabled: panel.root.opened && panel.visible && !panel.root.inert && !panel.navigationBlocked && !panel.switcherMode
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
    if (switcherMode) {
      switcher.reset()
      switcher.focusSearch()
    } else
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
  // Keyboard focus stays visible. A plain binding, deliberately not a Connections
  // on Window.window: retargeting one while the shell window is recreated crashed
  // the shell (QQmlConnections::setTarget).
  readonly property Item windowFocusItem: panel.Window.activeFocusItem
  onWindowFocusItemChanged: panel.revealFocus(windowFocusItem)
  // Projects already asked to seed this session (id → true); never re-requested.
  property var seededProjects: ({})
  // Project whose seed request is in flight, or ''.
  property string seedingProjectId: ''
  // The start block shows the project client's error while a start is uncertain or refused.
  readonly property bool startOwnsError: panel.root.projectClient.acceptanceUnknown || !!panel.root.projectClient.requestError
  // Project the automatic checks belong to; only a different project ends them.
  property string autoCheckProjectId: ''
  // Projects whose last seed request failed (id → the store's {code, message} or {}).
  property var seedFailures: ({})
  // Record (an error object, or {} when nothing came back) or clear (null) one project's seed failure.
  function setSeedFailure(projectId, failure) {
    var next = Object.assign({}, seedFailures)
    if (failure)
      next[projectId] = failure
    else
      delete next[projectId]
    seedFailures = next
  }
  // The selected project's seed failure, or null.
  readonly property var selectedSeedFailure: projectsPage.selectedProject ? seedFailures[projectsPage.selectedProject.id] || null : null
  // A probe that could not run differs from "no tools installed"; say which.
  readonly property bool seedProbeFailed: !!selectedSeedFailure && selectedSeedFailure.code === 'PROBE_FAILED'
  // The registry error is a stored seed failure of any project; only that project's header shows it.
  readonly property bool seedOwnsRegistryError: {
    var current = root.projectController.errorObject, failures = seedFailures
    return !!current && Object.keys(failures).some(function (id) {
      return failures[id] === current
    })
  }
  // Registry error text for the page box, without one the header already shows.
  readonly property string pageRegistryError: seedOwnsRegistryError ? '' : root.projectController.error
  // Ask the backend once per session to save defaults for a project without profiles.
  function requestSeed(projectId) {
    var client = root.projectController
    if (root.inert || !projectId || seededProjects[projectId] || seedingProjectId || client.pending || client.reading)
      return
    var project = (client.state.projects || []).find(function (p) {
      return p.id === projectId
    })
    if (!project || (project.profiles || []).length)
      return
    var next = Object.assign({}, seededProjects)
    next[projectId] = true
    seededProjects = next
    setSeedFailure(projectId, null)
    seedingProjectId = projectId
    if (!client.request('profiles-seed', {
      projectId: projectId
    })) {
      seedingProjectId = ''
      setSeedFailure(projectId, {})
    }
  }
  // Seed the selected project when it has no profiles and was not asked yet.
  function maybeSeedSelected() {
    var project = projectsPage.selectedProject
    if (project && !(project.profiles || []).length && !seededProjects[project.id])
      Qt.callLater(function () {
        panel.requestSeed(project.id)
      })
  }
  // Projects whose finished seed still left them with no profile (id → true).
  property var seedsMadeNothing: ({})
  // Record or clear one project's "seed made nothing" result.
  function setSeedMadeNothing(projectId, empty) {
    var next = Object.assign({}, seedsMadeNothing)
    if (empty)
      next[projectId] = true
    else
      delete next[projectId]
    seedsMadeNothing = next
  }
  // Forget a failed seed so the next request is allowed, then ask again.
  function retrySeed(projectId) {
    setSeedMadeNothing(projectId, false)
    var next = Object.assign({}, seededProjects)
    delete next[projectId]
    seededProjects = next
    requestSeed(projectId)
  }
  // Re-probe tools; a zero-profile project may seed again once tools exist.
  function refreshTools() {
    var project = projectsPage.selectedProject
    if (project && !(project.profiles || []).length && project.id !== seedingProjectId) {
      var next = Object.assign({}, seededProjects)
      delete next[project.id]
      seededProjects = next
      setSeedFailure(project.id, null)
      setSeedMadeNothing(project.id, false)
    }
    root.projectController.refresh()
  }
  // Project whose new task checkout form is open, or ''.
  property string taskFormProjectId: ''
  // Last task creation failure for the open form, or null.
  property var taskFormError: null
  // Linked checkout awaiting removal confirmation: {projectId, checkoutId}, or null.
  property var removeTarget: null
  // Removal check facts for the target, or null while checking.
  property var removeFacts: null
  // Last removal check or removal failure for the target, or null.
  property var removeError: null
  // The running task-remove call is the dry-run check, not the removal.
  property bool removeChecking: false
  // Last fetch or pull failure as {projectId, checkoutId, error}; shown only for that pair.
  property var gitCommandError: null
  // Running fetch or pull for the selected pair, or ''.
  readonly property string gitCommandPending: {
    var run = root.gitCommands.pending
    if (!run || (run.operation !== 'fetch' && run.operation !== 'pull'))
      return ''
    var project = projectsPage.selectedProject
    return project && run.projectId === project.id && run.checkoutId === root.gitClient.checkoutId ? run.operation : ''
  }
  // The stored fetch or pull failure when it belongs to the selected pair.
  readonly property var selectedGitCommandError: {
    var project = projectsPage.selectedProject, stored = gitCommandError
    return project && stored && stored.projectId === project.id && stored.checkoutId === root.gitClient.checkoutId ? stored.error : null
  }
  // The command ('fetch' or 'pull') behind the stored failure of the selected pair, or ''.
  readonly property string selectedGitCommandOperation: selectedGitCommandError ? gitCommandError.operation || '' : ''
  // Selected registered checkout record, or null.
  readonly property var selectedCheckout: {
    var project = projectsPage.selectedProject
    return project ? (project.checkouts || []).find(function (c) {
      return c.id === project.lastCheckoutId
    }) || null : null
  }
  // Last push or review-mark failure as {projectId, checkoutId, error}; shown only for that pair.
  property var reviewActionError: null
  // Review card model for the selected task checkout; state 'none' shows nothing.
  readonly property var reviewModel: {
    var project = projectsPage.selectedProject, checkout = selectedCheckout
    if (!project || !checkout || checkout.primary)
      return {
        state: 'none'
      }
    var snapshot = root.activityClient.snapshot || {}
    var tasks = Review.tasksFor(snapshot.tasks || [], project.id, checkout.id)
    var entry = root.reviewClient.reviews[checkout.id] || {}
    var mine = entry.projectId === project.id
    var data = mine && entry.data && entry.data.projectId === project.id ? entry.data : null
    var state = Review.reviewState(checkout, tasks, data)
    if (state !== 'ready')
      return {
        state: state
      }
    var definition = Review.checksAction(selectedDefinitions, project.id)
    var runs = definition ? Records.runs(root.actionClient.snapshot, project.id, checkout.id).filter(function (r) {
      return r.actionId === definition.id
    }) : []
    var client = root.actionClient
    var running = root.gitCommands.pending
    var stored = reviewActionError
    var storedMine = !!stored && stored.projectId === project.id && stored.checkoutId === checkout.id
    var terminal = (project.tools || {}).terminalId || (root.projectController.tools.defaults || {}).terminalId || ''
    var finished = Review.latestFinished(tasks)
    return {
      state: state,
      branch: checkout.branch || '',
      data: data,
      taskSummary: finished ? finished.result || finished.description || '' : '',
      // lastReceivedAt is in seconds; the card reads milliseconds.
      taskFinishedAt: finished && typeof finished.lastReceivedAt === 'number' ? finished.lastReceivedAt * 1000 : null,
      readError: !!(mine && entry.error),
      agentReport: Review.agentReportLabel(Review.latestFinished(tasks)),
      checksText: definition ? Review.checksLabel(runs[0] || null) : 'no check action saved',
      hasChecks: !!definition,
      canRunChecks: !!definition && !client.pending && !client.submissionUncertain && client.availability.execution === true && !Records.activeRun(client.snapshot, project.id, checkout.id, definition.id),
      canOpenDiff: !!data && !!data.mergeBase && !!terminal && !root.reviewClient.diffPending,
      pushPending: !!running && running.operation === 'push' && running.projectId === project.id && running.checkoutId === checkout.id,
      pushBlocked: !!running,
      markPending: root.projectController.pending,
      error: (storedMine ? stored.error : null) || (mine ? entry.error : null) || root.reviewClient.diffError || null
    }
  }
  // Agent tasks, for review markers.
  readonly property var markerTasks: (root.activityClient.snapshot || {}).tasks || []
  // Review helper data by checkout id, only where it belongs to the checkout's project.
  readonly property var markerReviews: {
    var out = {}
    var all = root.reviewClient.reviews || {}
    Object.keys(all).forEach(function (id) {
      var entry = all[id]
      if (entry && entry.data && entry.data.projectId === entry.projectId)
        out[id] = entry.data
    })
    return out
  }
  // Run the project's check action in the selected checkout; one press, one run.
  function runReviewChecks() {
    var project = projectsPage.selectedProject, checkout = selectedCheckout
    if (root.inert || !project || !checkout || !reviewModel.canRunChecks)
      return
    var definition = Review.checksAction(selectedDefinitions, project.id)
    if (definition)
      root.actionClient.start(definition.id, definition.revision)
  }
  // Open the saved terminal on the diff against the merge base.
  function openReviewDiff() {
    var project = projectsPage.selectedProject, checkout = selectedCheckout
    if (root.inert || !project || !checkout || !reviewModel.canOpenDiff)
      return
    var terminal = (project.tools || {}).terminalId || (root.projectController.tools.defaults || {}).terminalId || ''
    root.reviewClient.openDiff(checkout.path, reviewModel.data.mergeBase, terminal)
  }
  // Push the task branch; the helper never forces and never pushes another branch.
  function pushReviewBranch() {
    if (reviewModel.state !== 'ready')
      return
    if (runGit('push'))
      reviewActionError = null
  }
  // Record that this head and this task time were reviewed.
  function markReviewed() {
    var project = projectsPage.selectedProject, checkout = selectedCheckout
    if (root.inert || !project || !checkout || !reviewModel.data || reviewModel.markPending || reviewModel.readError)
      return
    var tasks = Review.tasksFor((root.activityClient.snapshot || {}).tasks || [], project.id, checkout.id)
    var latest = Review.latestFinished(tasks)
    reviewActionError = null
    root.projectController.request('review-mark', {
      projectId: project.id,
      checkoutId: checkout.id,
      head: reviewModel.data.head,
      taskFinishedAt: latest && typeof latest.lastReceivedAt === 'number' ? latest.lastReceivedAt : null
    })
  }
  // Start one Git command for the selected pair; false means nothing started.
  function runGit(operation, extra) {
    var project = projectsPage.selectedProject, checkoutId = root.gitClient.checkoutId
    if (root.inert || !project || !checkoutId)
      return false
    return root.gitCommands.run(operation, project.id, checkoutId, extra || [])
  }
  // Start a new task from the selected project's main checkout, never the selected one.
  function runTaskCreate(branch) {
    var project = projectsPage.selectedProject
    if (root.inert || !project)
      return false
    var primary = (project.checkouts || []).find(function (c) {
      return c.primary
    })
    return !!primary && root.gitCommands.run('task-create', project.id, primary.id, ['--branch', branch])
  }
  // A capture dropped a Git run and the registry has not been re-read since.
  property bool refreshAfterDrop: false
  // Re-read the registry once a dropped Git run can no longer be answered, outside capture.
  function refreshDroppedGit() {
    if (!refreshAfterDrop || root.inert)
      return
    refreshAfterDrop = false
    root.projectController.refresh()
  }
  // Open the removal card and run the dry-run check for one linked checkout.
  function requestTaskRemove(projectId, checkoutId) {
    if (root.inert)
      return
    removeTarget = {
      projectId: projectId,
      checkoutId: checkoutId
    }
    removeFacts = null
    removeError = null
    removeChecking = true
    if (!root.gitCommands.run('task-remove', projectId, checkoutId, ['--check'])) {
      removeChecking = false
      removeTarget = null
    }
  }
  // Close both task cards when the selection no longer matches them.
  function dropStaleTaskCards() {
    var project = projectsPage.selectedProject
    if (taskFormProjectId !== '' && (!project || project.id !== taskFormProjectId)) {
      taskFormProjectId = ''
      taskFormError = null
    }
    if (removeTarget && (!project || project.id !== removeTarget.projectId || project.lastCheckoutId !== removeTarget.checkoutId || !(project.checkouts || []).some(function (c) {
        return c.id === removeTarget.checkoutId
      })) && !(root.gitCommands.pending && root.gitCommands.pending.operation === 'task-remove')) {
      removeTarget = null
      removeFacts = null
      removeError = null
      removeChecking = false
    }
  }
  Connections {
    target: panel.root.gitCommands
    // A capture drops running Git work without a completion, so forget what waited on it.
    function onDropped() {
      panel.taskFormError = null
      panel.removeTarget = null
      panel.removeFacts = null
      panel.removeError = null
      panel.removeChecking = false
      panel.refreshAfterDrop = true
      panel.refreshDroppedGit()
    }
    function onEpochChanged() {
      panel.refreshDroppedGit()
    }
    function onFinished(operation, projectId, checkoutId, response) {
      var project = projectsPage.selectedProject
      if (operation === 'fetch' || operation === 'pull') {
        var stored = panel.gitCommandError
        if (!response.ok)
          panel.gitCommandError = {
            projectId: projectId,
            checkoutId: checkoutId,
            operation: operation,
            error: response.error
          }
        else if (stored && stored.projectId === projectId && stored.checkoutId === checkoutId)
          panel.gitCommandError = null
        if (project && project.id === projectId && panel.root.gitClient.checkoutId === checkoutId)
          panel.root.gitClient.refresh()
      } else if (operation === 'push') {
        panel.reviewActionError = response.ok ? null : {
          projectId: projectId,
          checkoutId: checkoutId,
          error: response.error
        }
        if (project && project.id === projectId && panel.root.gitClient.checkoutId === checkoutId)
          panel.root.gitClient.refresh()
      } else if (operation === 'task-create') {
        if (response.ok) {
          if (panel.taskFormProjectId === projectId) {
            panel.taskFormProjectId = ''
            panel.taskFormError = null
          }
          panel.root.projectController.refresh()
        } else if (panel.taskFormProjectId === projectId) {
          panel.taskFormError = response.error
        }
      } else if (operation === 'task-remove') {
        var target = panel.removeTarget
        var matches = !!target && target.projectId === projectId && target.checkoutId === checkoutId
        if (panel.removeChecking) {
          panel.removeChecking = false
          if (matches) {
            panel.removeFacts = response.ok ? response.data : null
            panel.removeError = response.ok ? null : response.error
          }
        } else if (response.ok) {
          panel.removeTarget = null
          panel.removeFacts = null
          panel.removeError = null
          panel.root.projectController.refresh()
        } else if (matches) {
          panel.removeError = response.error
        }
      }
    }
  }
  // Drop an in-flight seed whose project vanished or whose request capture cancelled.
  function dropStaleSeed() {
    if (!seedingProjectId)
      return
    var gone = !(root.projectController.state.projects || []).some(function (p) {
      return p.id === seedingProjectId
    })
    if (gone || root.inert)
      seedingProjectId = ''
  }
  Connections {
    target: panel.root
    function onInertChanged() {
      panel.dropStaleSeed()
    }
  }
  Connections {
    target: panel.root
    function onSelectedCheckoutIdChanged() {
      panel.root.projectClient.stopAutoCheck()
      panel.root.actionClient.stopAutoCheck()
    }
  }
  Connections {
    target: projectsPage
    function onSelectedProjectChanged() {
      // A registry refresh hands over a new object for the same project: only a different id ends the checks.
      var id = projectsPage.selectedProject ? projectsPage.selectedProject.id : ''
      if (id !== panel.autoCheckProjectId) {
        panel.autoCheckProjectId = id
        panel.root.projectClient.stopAutoCheck()
        panel.root.actionClient.stopAutoCheck()
      }
      panel.dropStaleTaskCards()
      panel.maybeSeedSelected()
    }
  }
  Connections {
    target: panel.root.projectController
    function onStateChanged() {
      panel.stampLayout()
      panel.scheduleGitBackground()
      panel.dropStaleSeed()
      panel.dropStaleTaskCards()
      panel.maybeSeedSelected()
    }
    function onToolsChanged() {
      panel.stampLayout()
    }
    function onMutationCompleted(action, args, state) {
      projectsPage.registryMutationCompleted(action, args, state)
      if (action === 'profiles-seed' && args.projectId === panel.seedingProjectId)
        panel.seedingProjectId = ''
      // Record what the seed made, not that it was asked for.
      if (action === 'profiles-seed') {
        var seeded = ((state || {}).projects || []).find(function (p) {
          return p.id === args.projectId
        })
        panel.setSeedMadeNothing(args.projectId, !!seeded && !(seeded.profiles || []).length)
      } else if (action === 'profile-save') {
        panel.setSeedMadeNothing(args.projectId, false)
      }
      panel.maybeSeedSelected()
    }
    function onMutationFailed(action, args) {
      if (action === 'profiles-seed' && args.projectId === panel.seedingProjectId) {
        panel.seedingProjectId = ''
        panel.setSeedFailure(args.projectId, panel.root.projectController.errorObject || {})
      }
    }
    function onPendingChanged() {
      panel.maybeSeedSelected()
    }
    function onReadingChanged() {
      panel.maybeSeedSelected()
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
  // Transparent catcher around the compact card; a click outside the card closes the switcher.
  MouseArea {
    objectName: 'projectSwitcherBackdrop'
    anchors.fill: parent
    enabled: panel.switcherMode && !panel.root.inert
    onClicked: function (mouse) {
      var inside = card.x <= mouse.x && mouse.x <= card.x + card.width && card.y <= mouse.y && mouse.y <= card.y + card.height
      if (!inside)
        panel.root.close()
    }
  }
  // Size of the compact card, capped to the surface.
  readonly property var switcherSize: Logic.switcherGeometry(width, height, Style.spaceReal(1))
  Aranea.SurfaceCard {
    id: card
    objectName: 'projectSwitcherCard'
    x: panel.switcherMode ? (panel.width - width) / 2 : 0
    y: panel.switcherMode ? (panel.height - height) / 2 : 0
    width: panel.switcherMode ? panel.switcherSize.width : panel.width
    height: panel.switcherMode ? panel.switcherSize.height : panel.height
    contentPadding: Style.space(16)
    fillColor: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 1)
    borderSpecOverride: Border.flat(Util.alpha(Commons.Color.foreground, 0.16), 1)
    ProjectSwitcher {
      id: switcher
      anchors.fill: parent
      anchors.margins: Style.space(panel.shortScreen ? 12 : 16)
      visible: panel.switcherMode
      projects: panel.root.projectController.state.projects || []
      navigation: panel.root.projectController.state.navigation || {}
      runtime: panel.root.projectClient.snapshot
      tools: panel.root.projectController.tools
      gitCache: panel.root.gitClient.cache
      tasks: panel.markerTasks
      reviews: panel.markerReviews
      client: panel.root.projectClient
      launching: !!panel.root.inspectionLaunchIntent
      displayOnly: panel.root.inert
      pointerGate: pointerGate
      systemBusy: panel.switcherPending
      loadProblem: !panel.seedOwnsRegistryError && (panel.root.projectController.error || panel.root.projectController.errorObject) ? Problems.problem(panel.root.projectController.errorObject || {
        message: panel.root.projectController.error
      }, {
        surface: 'switcher',
        actions: []
      }) : null
      onGoRequested: function (row) {
        panel.switcherGo(row)
      }
      onStartRequested: function (row) {
        panel.switcherStart(row)
      }
      onExpandRequested: function (id) {
        panel.switcherExpand(id)
      }
      onCloseRequested: panel.root.close()
      onVisibleChanged: if (visible)
        Qt.callLater(panel.focusKeys)
    }
    FocusScope {
      anchors.fill: parent
      anchors.margins: Style.space(panel.shortScreen ? 12 : 16)
      visible: !panel.switcherMode
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
              tasks: panel.markerTasks
              reviews: panel.markerReviews
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
                  color: Util.alpha(Commons.Color.foreground, 0.5)
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
                  pending: panel.root.projectClient.submitting || !!panel.root.inspectionLaunchIntent
                  acceptanceUnknown: panel.root.projectClient.acceptanceUnknown
                  displayOnly: !!panel.root.inert
                  pointerGate: pointerGate
                  tools: panel.root.projectController.tools
                  menuHost: panel
                  onStartProfile: function (id, revision) {
                    panel.root.startProfile(id, revision, false)
                  }
                  seeding: panel.seedingProjectId !== '' && !!projectsPage.selectedProject && panel.seedingProjectId === projectsPage.selectedProject.id
                  seedError: !panel.selectedSeedFailure ? '' : panel.seedProbeFailed ? "Couldn't check which tools are installed." : "Couldn't prepare a default profile."
                  seedRetryLabel: panel.seedProbeFailed ? 'Check again' : 'Retry'
                  seedMadeNothing: !!projectsPage.selectedProject && !!panel.seedsMadeNothing[projectsPage.selectedProject.id]
                  onRefreshToolsRequested: panel.refreshTools()
                  onRetrySeedRequested: panel.retrySeed(projectsPage.selectedProject.id)
                  onManageProfilesRequested: panel.chooseSection('profiles')
                  onTaskCreateRequested: function (projectId) {
                    if (panel.root.inert)
                      return
                    panel.removeTarget = null
                    panel.taskFormProjectId = projectId
                    panel.taskFormError = null
                  }
                  onTaskRemoveRequested: function (projectId, checkoutId) {
                    panel.taskFormProjectId = ''
                    panel.requestTaskRemove(projectId, checkoutId)
                  }
                }
                ProjectTaskForm {
                  width: content.width
                  visible: !!projectsPage.selectedProject && !projectsPage.setupActive && panel.taskFormProjectId !== '' && projectsPage.selectedProject.id === panel.taskFormProjectId
                  project: projectsPage.selectedProject
                  pending: !!panel.root.gitCommands.pending && panel.root.gitCommands.pending.operation === 'task-create' && panel.root.gitCommands.pending.projectId === panel.taskFormProjectId
                  blocked: !!panel.root.gitCommands.pending
                  error: panel.taskFormError
                  displayOnly: !!panel.root.inert
                  pointerGate: pointerGate
                  onCreateRequested: function (branch) {
                    panel.taskFormError = null
                    panel.runTaskCreate(branch)
                  }
                  onCancelled: {
                    panel.taskFormProjectId = ''
                    panel.taskFormError = null
                  }
                }
                ProjectTaskRemove {
                  width: content.width
                  visible: !!projectsPage.selectedProject && !projectsPage.setupActive && !!panel.removeTarget && panel.removeTarget.projectId === projectsPage.selectedProject.id && panel.removeTarget.checkoutId === projectsPage.selectedProject.lastCheckoutId
                  checkout: panel.selectedCheckout
                  facts: panel.removeFacts
                  pending: !!panel.root.gitCommands.pending && panel.root.gitCommands.pending.operation === 'task-remove' && !panel.removeChecking
                  blocked: !!panel.root.gitCommands.pending
                  error: panel.removeError
                  displayOnly: !!panel.root.inert
                  pointerGate: pointerGate
                  onConfirmRequested: function (confirmUnpushed) {
                    var target = panel.removeTarget
                    if (panel.root.inert || !target)
                      return
                    panel.removeError = null
                    panel.removeChecking = false
                    panel.root.gitCommands.run('task-remove', target.projectId, target.checkoutId, confirmUnpushed ? ['--confirm-unpushed'] : [])
                  }
                  onCancelled: {
                    panel.removeTarget = null
                    panel.removeFacts = null
                    panel.removeError = null
                  }
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
                  visible: !!panel.root.inspectionError
                  text: panel.root.inspectionError
                  color: Aranea.DesignTokens.urgent
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
                  registryState: panel.root.presentationState
                  tools: panel.root.projectController.tools
                  agentChoice: panel.agentChoice
                  discoveryClient: panel.root.discoveryClient
                  projectClient: panel.root.projectClient
                  projectId: panel.root.projectId
                  displayOnly: !!panel.root.inert
                  windowOpen: !!panel.root.opened
                  metadataPending: panel.root.navigationSaving
                  pending: panel.root.projectController.pending || panel.root.projectController.reading
                  error: panel.pageRegistryError || (panel.startOwnsError ? '' : panel.root.projectClient.error)
                  extraErrorObject: panel.root.projectController.extraErrorObject
                  errorObject: (panel.seedOwnsRegistryError ? null : panel.root.projectController.errorObject) || (!panel.pageRegistryError && !panel.startOwnsError && panel.root.projectClient.error ? {
                      message: panel.root.projectClient.error
                    } : null)
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
                    if (panel.root.inspectionCheckoutId && payload.projectId === panel.root.projectId && payload.checkoutId === undefined)
                      payload = Object.assign({}, payload, {
                        checkoutId: panel.root.inspectionCheckoutId
                      })
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
                    objectName: 'projectPreparing'
                    Layout.fillWidth: true
                    visible: panel.root.projectClient.preparing && !panel.root.projectClient.acceptanceUnknown
                    text: 'Preparing this profile…'
                    color: Aranea.DesignTokens.attention
                  }
                  ProjectProblem {
                    id: startProblem
                    objectName: 'projectStartProblem'
                    Layout.fillWidth: true
                    displayOnly: panel.root.inert
                    actionsEnabled: !panel.root.projectClient.submitting
                    pointerGate: pointerGate
                    readonly property var client: panel.root.projectClient
                    // Remembered profile that Start another would reuse.
                    readonly property var another: projectsPage.selectedProject ? Profiles.remembered(projectsPage.selectedProject) : null
                    problem: {
                      if (!projectsPage.selectedProject || client.preparing && !client.acceptanceUnknown || client.autoChecking)
                        return null
                      if (!client.acceptanceUnknown && !client.requestError)
                        return null
                      var error = client.requestError || {
                        code: 'ACCEPTANCE_UNKNOWN',
                        message: client.error
                      }
                      var actions = []
                      if (client.acceptanceUnknown) {
                        actions.push('checkAgain')
                        if (startProblem.another)
                          actions.push('startAnother')
                      }
                      var plain = Problems.problem(error, {
                        surface: 'start',
                        actions: actions
                      })
                      // The activation and earlier unresolved requests stay available under Details.
                      if (client.acceptanceUnknown)
                        plain.details.recovery = [plain.details.recovery, 'Request: ' + client.activationId, 'Earlier unresolved requests: ' + client.unresolvedEnvironmentActivations.length].filter(Boolean).join('\n')
                      return plain
                    }
                    onActionRequested: function (id) {
                      if (id === 'checkAgain') {
                        if (!panel.root.inert && !startProblem.client.submitting)
                          startProblem.client.checkEnvironmentActivation()
                      } else if (id === 'startAnother' && startProblem.another && !panel.root.inert && !startProblem.client.submitting) {
                        panel.root.startProfile(startProblem.another.id, startProblem.another.revision, true)
                      }
                    }
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
                      text: 'Manage profiles'
                      visible: !panel.root.projectClient.acceptanceUnknown && !panel.root.projectClient.preparing
                      pointerGate: pointerGate
                      onClicked: panel.chooseSection('profiles')
                    }
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
                  actionObservationAvailable: panel.root.inert || panel.root.actionClient.available
                  agentObservationAvailable: panel.root.inert || panel.root.activityClient.available
                  agentPending: panel.root.activityClient.pending
                  workspacePending: panel.root.projectClient.submitting || panel.root.projectClient.acceptanceUnknown || !projectsPage.details.openAvailable
                  executionAvailable: panel.root.actionClient.availability.execution === true
                  actionProblem: panel.root.actionClient.submissionUncertain ? (panel.root.actionClient.autoChecking ? null : {
                      code: 'SUBMISSION_UNCONFIRMED'
                    }) : panel.root.actionClient.error || panel.root.actionClient.summaryError || null
                  onActionRefreshRequested: {
                    if (!panel.root.inert && !panel.root.actionClient.pending)
                      panel.root.actionClient.refresh()
                  }
                  actionError: !panel.root.actionClient.submissionUncertain && !panel.root.actionClient.error && !panel.root.actionClient.summaryError && panel.root.actionClient.available && panel.overviewModel.services.concat(panel.overviewModel.checks).length && panel.root.actionClient.availability.execution !== true ? 'Running is not available. Manage actions to check required helpers.' : ''
                  activityError: panel.root.activityClient.error ? 'Agent connection not available. Open Details to reconnect.' : ''
                  pointerGate: pointerGate
                  suggestions: panel.overviewSuggestions
                  onSuggestionAddRequested: function (key) {
                    panel.addOverviewSuggestion(key)
                  }
                  gitCommandPending: panel.gitCommandPending
                  gitCommandError: panel.selectedGitCommandError
                  gitCommandOperation: panel.selectedGitCommandOperation
                  gitCommandBusy: !!panel.root.gitCommands.pending
                  review: panel.reviewModel
                  onReviewRunChecksRequested: panel.runReviewChecks()
                  onReviewOpenDiffRequested: panel.openReviewDiff()
                  onReviewPushRequested: panel.pushReviewBranch()
                  onReviewMarkRequested: panel.markReviewed()
                  onReviewRemoveRequested: {
                    var project = projectsPage.selectedProject
                    if (project && panel.selectedCheckout)
                      panel.requestTaskRemove(project.id, panel.selectedCheckout.id)
                  }
                  onRefreshRequested: panel.refreshOverview()
                  onFetchRequested: panel.runGit('fetch')
                  onPullRequested: panel.runGit('pull')
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
