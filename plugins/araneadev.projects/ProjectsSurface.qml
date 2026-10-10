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

Item {
  id: panel
  // Persistent presentation entry owns clients and visibility.
  required property var root
  // Narrow widths use a compact selector instead of the tall sidebar.
  readonly property bool compact: width < Style.space(720)
  // Reduce window chrome on short logical screens.
  readonly property bool shortScreen: height < Style.space(400)
  // Current project destination, retained independently of window visibility.
  property string section: 'overview'
  // Activity observations run only while the selected Agents destination is visible.
  readonly property bool activityVisible: section === 'agents' && !projectsPage.setupActive && !!projectsPage.selectedProject
  // Latest geometry/content change disarms stale pointer activation.
  property real layoutChangedAt: 0
  // Unsaved drafts, wizard state and pending work prevent changing selection.
  readonly property bool navigationBlocked: projectsPage.setupActive || projectsPage.setupNavigationPending || projectsPage.details.dirty || projectsPage.details.actions.editing || root.activityClient.pending
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
    root.projectId = id
    section = 'overview'
    scrollTo(0)
    stampLayout()
    return true
  }
  // Choose a supported destination after checking draft and pending guards.
  function chooseSection(next) {
    if (['overview', 'actions', 'agents', 'preferences', 'help'].indexOf(next) < 0)
      return false
    if (next !== section && (projectsPage.details.dirty || projectsPage.details.actions.editing || projectsPage.setupNavigationPending || root.activityClient.pending))
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
    Qt.callLater(function () {
      panel.scrollTo(saved.contentY || 0)
    })
  }
  // Initialize inert fixture presentation without invoking an owner operation.
  function captureReset(fixture) {
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
  Connections {
    target: panel.root.projectController
    function onStateChanged() {
      panel.stampLayout()
    }
    function onToolsChanged() {
      panel.stampLayout()
    }
    function onMutationCompleted(action, args, state) {
      projectsPage.registryMutationCompleted(action, args, state)
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
            visible: !projectsPage.setupActive
            Layout.fillWidth: panel.compact
            Layout.preferredWidth: panel.compact ? -1 : Style.space(260)
            Layout.fillHeight: !panel.compact
            implicitHeight: panel.compact ? sidebar.implicitHeight + Style.space(24) : 0
            radius: Style.space(6)
            color: Util.alpha(Color.foreground, 0.025)
            border.color: Util.alpha(Color.foreground, 0.08)
            border.width: 1
            ProjectsSidebar {
              id: sidebar
              anchors.fill: parent
              anchors.margins: Style.space(12)
              compact: panel.compact
              projects: panel.root.projectController.state.projects || []
              bindings: panel.root.projectClient.snapshot.bindings || []
              selectedId: projectsPage.selectedProject ? projectsPage.selectedProject.id : panel.root.projectId
              navigationEnabled: !panel.navigationBlocked && !panel.root.inert
              pointerGate: pointerGate
              onProjectRequested: function (id) {
                panel.navigate(id)
              }
              onSetupRequested: projectsPage.startSetup()
              onViewportChanged: panel.stampLayout()
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
                  project: projectsPage.selectedProject
                  bindings: panel.root.projectClient.snapshot.bindings || []
                  openAvailable: projectsPage.details.openAvailable
                  pending: projectsPage.details.pending
                  displayOnly: !!panel.root.inert
                  pointerGate: pointerGate
                  onOpenRequested: {
                    if (['agents', 'help'].indexOf(panel.section) < 0 || panel.chooseSection('overview'))
                      projectsPage.details.openProject()
                  }
                }
                Aranea.PageHeader {
                  width: content.width
                  visible: projectsPage.setupActive
                  title: 'Add a project'
                  description: 'Choose a repository, configure your tools, and connect agent reporting if you need it.'
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
                      enabled: (modelData.id === 'help' || modelData.id === 'preferences' || !!projectsPage.selectedProject) && (panel.section === modelData.id || !projectsPage.details.dirty && !projectsPage.details.actions.editing && !projectsPage.setupNavigationPending && !panel.root.activityClient.pending)
                      pointerGate: pointerGate
                      onClicked: panel.chooseSection(modelData.id)
                    }
                  }
                }
                ProjectsWelcome {
                  width: content.width
                  visible: !projectsPage.selectedProject && !projectsPage.setupActive && panel.section !== 'help' && panel.section !== 'preferences'
                  hasProjects: (panel.root.projectController.state.projects || []).length > 0
                  pending: panel.navigationBlocked
                  displayOnly: !!panel.root.inert
                  pointerGate: pointerGate
                  onSetupRequested: projectsPage.startSetup()
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
                  discoveryClient: panel.root.discoveryClient
                  projectClient: panel.root.projectClient
                  projectId: panel.root.projectId
                  displayOnly: !!panel.root.inert
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
                    panel.navigate(id)
                  }
                  onRefreshRequested: {
                    panel.root.projectController.refresh()
                    panel.root.projectClient.refresh()
                  }
                }
                ProjectAgents {
                  id: agentsView
                  width: scroller.contentWidth
                  visible: panel.section === 'agents' && !!projectsPage.selectedProject && !projectsPage.setupActive
                  project: projectsPage.selectedProject
                  registry: panel.root.projectController.state
                  client: panel.root.activityClient
                  displayOnly: !!panel.root.inert
                  maxHeight: Math.max(Style.space(200), scroller.height)
                  onSetupRequested: projectsPage.startSetup()
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
          text: projectsPage.setupActive ? 'Complete or exit setup before switching projects.' : panel.navigationBlocked ? 'Save or discard drafts before switching projects.' : panel.root.captureSaved ? 'Preview · read-only' : 'Tab navigate · Page Up/Down scroll · Esc close'
          opacity: 0.5
        }
      }
    }
  }
}
