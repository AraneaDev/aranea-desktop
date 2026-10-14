// qmllint disable missing-property
// Search and stable project selection; presentation never launches applications.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea
import "ProjectsNavigation.js" as Navigation

ColumnLayout {
  id: sidebar
  objectName: 'projectsSidebar'
  // Saved registrations; display labels never become executable arguments.
  property var projects: []
  // Observed workspace associations from the persistent project owner.
  property var bindings: []
  // Opaque selected project identity, independent of row ordering.
  property string selectedId: ''
  // Local search draft; filtering performs no backend work.
  property string query: ''
  // Generic choosers supply an appropriate search prompt.
  property string searchPlaceholder: 'Search projects…'
  // Optional already-projected rows let the picker share search/list presentation.
  property var rows: null
  // Saved navigation metadata stays separate from registration and launch state.
  property var navigation: ({})
  // Compatibility layout flag; compact hosts now open a full picker.
  property bool compact: false
  // Host draft and pending guards disable project changes.
  property bool navigationEnabled: true
  // Picker consumers hide project-specific registration controls.
  property bool showAddProject: true
  // A single quiet pin control is available only for project navigation.
  property bool pinningEnabled: true
  // Shared pointer movement and layout settling guard.
  property var pointerGate: null
  // Freeze identities only while the current query is being navigated.
  property var frozenIds: []
  // Keyboard cursor is an identity, never a transient result position.
  property string highlightedId: ''
  // Project matching includes every known checkout branch and path.
  readonly property var filteredProjects: rows !== null ? rows : Navigation.rows(projects, navigation, query, frozenIds)
  // Keep delegates keyed by exact identity so publication cannot destroy focused controls.
  function syncRows() {
    for (var i = 0; i < filteredProjects.length; i++) {
      var row = filteredProjects[i]
      var found = -1
      for (var j = i; j < projectModel.count; j++) {
        if (projectModel.get(j).row.id === row.id) {
          found = j
          break
        }
      }
      if (found < 0)
        projectModel.insert(i, {
          row: row
        })
      else {
        if (found !== i)
          projectModel.move(found, i, 1)
        projectModel.setProperty(i, 'row', row)
      }
    }
    if (projectModel.count > filteredProjects.length)
      projectModel.remove(filteredProjects.length, projectModel.count - filteredProjects.length)
  }
  onFilteredProjectsChanged: syncRows()
  Component.onCompleted: syncRows()
  ListModel {
    id: projectModel
  }
  // Focus the existing search field without moving focus during refresh.
  function focusSearch() {
    freezeOrder()
    projectSearch.forceActiveFocus()
  }
  // Keep metadata refreshes from moving rows under keyboard or pointer input.
  function freezeOrder() {
    frozenIds = filteredProjects.map(function (row) {
      return row.id
    })
  }
  // Arrow keys inspect the result list; Enter selects without launching.
  function handleSearchKey(event) {
    if (!navigationEnabled)
      return
    var index = filteredProjects.findIndex(function (row) {
      return row.id === highlightedId
    })
    if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
      freezeOrder()
      index = Math.max(0, Math.min(filteredProjects.length - 1, index + (event.key === Qt.Key_Down ? 1 : -1)))
      highlightedId = filteredProjects[index] ? filteredProjects[index].id : ''
      revealRow(projectRows.itemAt(index))
      event.accepted = true
    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && index >= 0) {
      projectRequested(highlightedId)
      event.accepted = true
    }
  }
  // Persist a pin using the stable supplied row identity.
  signal pinRequested(string id, bool pinned)
  // Vertical position is presentation state, retained by scoped captures.
  property alias contentY: projectList.contentY
  // Moving the list invalidates pointer presses made before that movement.
  signal viewportChanged
  // Public viewport projection includes clipped rows but excludes wholly offscreen rows.
  function visibleProjectIds() {
    if (!visible || compact || projectList.height <= 0)
      return []
    var ids = []
    for (var i = 0; i < projectRows.count && ids.length < 12; i++) {
      var row = projectRows.itemAt(i)
      if (row && row.y + row.height > projectList.contentY && row.y < projectList.contentY + projectList.height)
        ids.push(row.modelData.id)
    }
    return ids
  }
  // Clamp scrolling to the visible project list without changing selection.
  function scrollTo(y) {
    projectList.cancelFlick()
    projectList.contentY = Math.max(0, Math.min(y, Math.max(0, projectList.contentHeight - projectList.height)))
  }
  // Keep the complete keyboard-focused row in the project's viewport.
  function revealRow(row) {
    if (!row || sidebar.compact)
      return
    var pos = row.mapToItem(projectList.contentItem, 0, 0)
    if (row.height > projectList.height || pos.y < projectList.contentY)
      scrollTo(pos.y)
    else if (pos.y + row.height > projectList.contentY + projectList.height)
      scrollTo(pos.y + row.height - projectList.height)
  }
  // Restore scroll only after filtering and delegates have settled.
  function restoreViewport(y) {
    Qt.callLater(function () {
      sidebar.scrollTo(y)
    })
  }
  onQueryChanged: {
    frozenIds = []
    highlightedId = ''
    if (query)
      freezeOrder()
    restoreViewport(0)
  }
  onSelectedIdChanged: Qt.callLater(function () {
    var index = sidebar.filteredProjects.findIndex(function (p) {
      return p.id === sidebar.selectedId
    })
    if (index >= 0)
      sidebar.revealRow(projectRows.itemAt(index))
  })
  Keys.onPressed: function (event) {
    if (sidebar.compact)
      return
    if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
      sidebar.scrollTo(projectList.contentY + (event.key === Qt.Key_PageDown ? 1 : -1) * projectList.height * 0.9)
      event.accepted = true
    } else if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
      sidebar.scrollTo(event.key === Qt.Key_Home ? 0 : projectList.contentHeight)
      event.accepted = true
    }
  }
  // Request explicit selection of one stable project identity.
  signal projectRequested(string id)
  // Start the existing setup wizard after the host checks draft guards.
  signal setupRequested
  // Describe only an observed workspace association for this identity.
  function workspaceLabel(id) {
    var binding = bindings.filter(function (v) {
      return v.projectId === id
    })[0]
    return binding && binding.workspaceId !== undefined ? ' · Workspace ' + binding.workspaceId : ''
  }
  // Short path hints keep duplicate names distinguishable within compact rows.
  function folderLabel(row) {
    var path = row.path || ''
    var parts = path.split('/').filter(function (part) {
      return !!part
    })
    return parts.length > 2 ? '…/' + parts.slice(-2).join('/') : path || 'No checkout'
  }
  spacing: Style.space(8)
  Aranea.UiLabel {
    Layout.fillWidth: true
    text: 'PROJECTS' + (sidebar.projects.length ? ' · ' + sidebar.projects.length : '')
    visible: sidebar.showAddProject
    font.bold: true
    opacity: 0.55
  }
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(8)
    TextField {
      id: projectSearch
      objectName: 'projectSearch'
      Layout.fillWidth: true
      placeholderText: sidebar.searchPlaceholder
      palette.placeholderText: Util.alpha(Color.foreground, 0.55)
      text: sidebar.query
      onTextEdited: sidebar.query = text
      enabled: sidebar.navigationEnabled
      Keys.onPressed: function (event) {
        sidebar.handleSearchKey(event)
      }
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.body
      color: Color.foreground
      background: Rectangle {
        color: Util.alpha(Color.foreground, 0.06)
        radius: Style.space(3)
      }
    }
    Aranea.ActionButton {
      objectName: 'resetProjectQuery'
      text: 'Clear'
      visible: !!sidebar.query
      variant: 'quiet'
      enabled: sidebar.navigationEnabled
      pointerGate: sidebar.pointerGate
      onClicked: {
        sidebar.query = ''
        sidebar.focusSearch()
      }
    }
  }
  Flickable {
    id: projectList
    objectName: 'projectsList'
    Layout.fillWidth: true
    Layout.fillHeight: true
    clip: true
    contentWidth: Math.max(1, width - Style.space(16))
    contentHeight: rowColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    onContentYChanged: sidebar.viewportChanged()
    ScrollBar.vertical: ScrollBar {
      objectName: 'projectsListScrollBar'
      parent: projectList
      anchors.right: projectList.right
      anchors.top: projectList.top
      anchors.bottom: projectList.bottom
      width: Style.space(14)
      active: projectList.contentHeight > projectList.height + 1
      policy: projectList.contentHeight > projectList.height + 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
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
    ColumnLayout {
      id: rowColumn
      width: projectList.contentWidth
      spacing: Style.space(4)
      Repeater {
        id: projectRows
        model: projectModel
        Aranea.ActionButton {
          id: projectRow
          required property var row
          // The keyed model updates labels in place while retaining delegate children.
          readonly property var modelData: row
          required property int index
          Layout.fillWidth: true
          implicitHeight: Math.max(Style.space(48), rowLabels.implicitHeight + Style.space(16))
          objectName: 'selectProject:' + modelData.id
          text: modelData.name
          // Full labels remain available when compact name/path text is elided.
          readonly property string fullLabel: modelData.name + (modelData.branch ? ' · ' + modelData.branch : '') + (modelData.path ? '\n' + modelData.path : '')
          variant: 'navigation'
          selected: sidebar.selectedId === modelData.id || sidebar.highlightedId === modelData.id
          enabled: sidebar.navigationEnabled
          Accessible.name: fullLabel
          pointerGate: sidebar.pointerGate
          onActiveFocusChanged: if (activeFocus) {
            sidebar.highlightedId = modelData.id
            sidebar.freezeOrder()
            sidebar.revealRow(projectRow)
          }
          KeyNavigation.up: index > 0 ? projectRows.itemAt(index - 1) : projectSearch
          KeyNavigation.down: index + 1 < sidebar.filteredProjects.length ? projectRows.itemAt(index + 1) : addProject
          ToolTip.visible: rowHover.hovered
          ToolTip.text: fullLabel
          HoverHandler {
            id: rowHover
          }
          Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(8)
            width: Style.space(2)
            radius: width / 2
            visible: projectRow.selected
            color: Aranea.DesignTokens.accent
          }
          Column {
            id: rowLabels
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: sidebar.pinningEnabled ? Style.space(52) : Style.space(8)
            spacing: Style.space(3)
            Aranea.UiLabel {
              width: parent.width
              objectName: 'projectRowName'
              text: projectRow.modelData.name
              font.pixelSize: Style.font.body
              font.bold: projectRow.selected
              wrapMode: Text.NoWrap
              elide: Text.ElideRight
            }
            Aranea.UiLabel {
              width: parent.width
              visible: !!projectRow.modelData.path || !!projectRow.modelData.branch
              text: (projectRow.modelData.branch || 'detached') + sidebar.workspaceLabel(projectRow.modelData.id)
              elide: Text.ElideRight
              wrapMode: Text.NoWrap
            }
            Aranea.UiLabel {
              width: parent.width
              objectName: 'projectRowPath'
              visible: !!projectRow.modelData.path || sidebar.showAddProject
              text: sidebar.folderLabel(projectRow.modelData)
              opacity: 0.7
              wrapMode: Text.NoWrap
              elide: Text.ElideMiddle
            }
          }
          Aranea.ActionButton {
            objectName: 'pinProject:' + projectRow.modelData.id
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(44)
            text: projectRow.modelData.pinned ? 'Unpin' : 'Pin'
            variant: 'quiet'
            visible: sidebar.pinningEnabled
            enabled: sidebar.navigationEnabled
            pointerGate: sidebar.pointerGate
            Accessible.name: (projectRow.modelData.pinned ? 'Unpin ' : 'Pin ') + projectRow.modelData.name
            onClicked: sidebar.pinRequested(projectRow.modelData.id, !projectRow.modelData.pinned)
          }
          onClicked: sidebar.projectRequested(modelData.id)
        }
      }
      Aranea.UiLabel {
        Layout.fillWidth: true
        visible: sidebar.filteredProjects.length === 0
        text: sidebar.query ? 'No matching results.' : sidebar.showAddProject ? 'Add your first project.' : 'No entries available.'
        opacity: 0.65
      }
    }
  }
  Aranea.ActionButton {
    id: addProject
    objectName: 'sidebarAddProject'
    visible: sidebar.showAddProject
    Layout.fillWidth: true
    text: 'Add project'
    variant: 'primary'
    enabled: sidebar.navigationEnabled
    pointerGate: sidebar.pointerGate
    onClicked: sidebar.setupRequested()
  }
}
