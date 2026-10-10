// qmllint disable missing-property
// Search and stable project selection; presentation never launches applications.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

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
  // Narrow widths use a compact selector instead of the tall sidebar.
  property bool compact: false
  // Host draft and pending guards disable project changes.
  property bool navigationEnabled: true
  // Shared pointer movement and layout settling guard.
  property var pointerGate: null
  // Case-insensitive local search over names and exact checkout paths.
  readonly property var filteredProjects: projects.filter(function (p) {
    var value = query.toLowerCase()
    return (p.name || '').toLowerCase().indexOf(value) >= 0 || (p.checkouts || []).some(function (c) {
      return (c.path || '').toLowerCase().indexOf(value) >= 0
    })
  })
  // Vertical position is presentation state, retained by scoped captures.
  property alias contentY: projectList.contentY
  // Moving the list invalidates pointer presses made before that movement.
  signal viewportChanged
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
  onQueryChanged: restoreViewport(0)
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
  // Keep a readable folder hint while the full path remains available on hover.
  function folderLabel(project) {
    var checkout = (project.checkouts || []).filter(function (c) {
      return c.id === project.lastCheckoutId
    })[0] || (project.checkouts || [])[0]
    if (!checkout)
      return 'No checkout'
    var parts = checkout.path.split('/').filter(function (part) {
      return !!part
    })
    return parts.length > 2 ? '…/' + parts.slice(-2).join('/') : checkout.path
  }
  spacing: Style.space(8)
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: !sidebar.compact
    text: 'PROJECTS' + (sidebar.projects.length ? ' · ' + sidebar.projects.length : '')
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
      placeholderText: 'Search projects…'
      palette.placeholderText: Util.alpha(Color.foreground, 0.55)
      text: sidebar.query
      onTextEdited: sidebar.query = text
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.body
      color: Color.foreground
      background: Rectangle {
        color: Util.alpha(Color.foreground, 0.06)
        radius: Style.space(3)
      }
    }
    Aranea.ActionButton {
      text: 'Add project'
      visible: sidebar.compact
      variant: 'primary'
      enabled: sidebar.navigationEnabled
      pointerGate: sidebar.pointerGate
      onClicked: sidebar.setupRequested()
    }
  }
  ComboBox {
    objectName: 'compactProjectSelector'
    visible: sidebar.compact
    Layout.fillWidth: true
    model: sidebar.filteredProjects
    palette.text: Color.foreground
    palette.buttonText: Color.foreground
    palette.base: Color.background
    palette.button: Util.alpha(Color.foreground, 0.08)
    palette.window: Color.background
    palette.highlight: Aranea.DesignTokens.accent
    palette.highlightedText: Color.foreground
    background: Rectangle {
      color: Util.alpha(Color.foreground, 0.06)
      radius: Style.space(3)
      border.color: Util.alpha(Color.foreground, 0.16)
    }
    popup.popupType: Popup.Item
    popup.background: Rectangle {
      color: Color.background
      border.color: Util.alpha(Color.foreground, 0.16)
      radius: Style.space(3)
    }
    textRole: 'name'
    valueRole: 'id'
    currentIndex: sidebar.filteredProjects.findIndex(function (p) {
      return p.id === sidebar.selectedId
    })
    enabled: sidebar.navigationEnabled
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: Style.font.body
    onActivated: function (index) {
      sidebar.projectRequested(sidebar.filteredProjects[index].id)
    }
  }
  Flickable {
    id: projectList
    objectName: 'projectsList'
    visible: !sidebar.compact
    Layout.fillWidth: true
    Layout.fillHeight: true
    clip: true
    contentWidth: Math.max(1, width - Style.space(16))
    contentHeight: rows.implicitHeight
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
      id: rows
      width: projectList.contentWidth
      spacing: Style.space(4)
      Repeater {
        id: projectRows
        model: sidebar.filteredProjects
        Aranea.ActionButton {
          id: projectRow
          required property var modelData
          required property int index
          Layout.fillWidth: true
          implicitHeight: Math.max(Style.space(48), rowLabels.implicitHeight + Style.space(16))
          objectName: 'selectProject:' + modelData.id
          text: modelData.name
          variant: 'navigation'
          selected: sidebar.selectedId === modelData.id
          enabled: sidebar.navigationEnabled
          Accessible.name: modelData.name + ' · ' + sidebar.folderLabel(modelData)
          pointerGate: sidebar.pointerGate
          onActiveFocusChanged: if (activeFocus)
            sidebar.revealRow(projectRow)
          KeyNavigation.up: index > 0 ? projectRows.itemAt(index - 1) : projectSearch
          KeyNavigation.down: index + 1 < sidebar.filteredProjects.length ? projectRows.itemAt(index + 1) : addProject
          ToolTip.visible: rowHover.hovered
          ToolTip.text: (modelData.checkouts || []).map(function (c) {
            return c.path
          }).join('\n')
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
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(3)
            Aranea.UiLabel {
              width: parent.width
              objectName: 'projectRowName'
              text: projectRow.modelData.name
              font.pixelSize: Style.font.body
              font.bold: projectRow.selected
              wrapMode: Text.Wrap
            }
            Aranea.UiLabel {
              width: parent.width
              text: sidebar.folderLabel(projectRow.modelData) + sidebar.workspaceLabel(projectRow.modelData.id)
              opacity: 0.7
              wrapMode: Text.Wrap
            }
          }
          onClicked: sidebar.projectRequested(modelData.id)
        }
      }
      Aranea.UiLabel {
        Layout.fillWidth: true
        visible: sidebar.filteredProjects.length === 0
        text: sidebar.projects.length ? 'No matching projects.' : 'Add your first project.'
        opacity: 0.65
      }
    }
  }
  Aranea.ActionButton {
    id: addProject
    objectName: 'sidebarAddProject'
    Layout.fillWidth: true
    visible: !sidebar.compact
    text: 'Add project'
    variant: 'primary'
    enabled: sidebar.navigationEnabled
    pointerGate: sidebar.pointerGate
    onClicked: sidebar.setupRequested()
  }
}
