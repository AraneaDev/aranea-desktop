// Searchable supplied-row chooser shared by projects and registered checkouts.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import "../araneadev.shared" as Aranea

Popup {
  id: picker
  // Rows carry exact IDs and readable names, paths, and optional branches.
  property var rows: []
  // Current inspected identity; opening never activates it.
  property string selectedId: ''
  // Retained query draft is owned by the host.
  property string query: ''
  // Context-specific prompt; project and checkout consumers retain the default.
  property string searchPlaceholder: 'Search…'
  // Shared host layout settling guard.
  property var pointerGate: null
  // Inert capture hosts refuse pointer, keyboard, and programmatic activation.
  property bool displayOnly: false
  // Projects expose pinning; generic choosers leave it disabled.
  property bool pinningEnabled: false
  // Project pickers keep registration reachable at narrow widths.
  property bool showAddProject: false
  // Profile choosers omit checkout-specific branch and path shortening.
  property bool showCheckoutContext: true
  // The surface applies its draft decision before opening registration.
  signal setupRequested
  // Hosts may project branch matches from all checkouts before supplying rows.
  property bool rowsFiltered: false
  // Query order is supplied to the host's pure navigation projection.
  property alias frozenIds: list.frozenIds
  // Exact selected identity, without any workspace or application launch.
  signal selected(string id)
  // Host can restore focus after any dismissal.
  signal dismissed
  // Route all activation paths through the same inert boundary.
  function select(id) {
    if (displayOnly || !list.filteredProjects.some(function (row) {
      return row.id === id
    }))
      return
    selected(id)
    close()
  }
  // Forward pin changes without choosing or launching the row.
  signal pinRequested(string id, bool pinned)
  // Reset only for an explicit new query, preserving ordering during refresh.
  onQueryChanged: list.query = query
  onDisplayOnlyChanged: if (displayOnly)
    close()
  onAboutToShow: {
    if (displayOnly) {
      close()
      return
    }
    list.query = query
    Qt.callLater(function () {
      if (picker.opened)
        list.focusSearch()
    })
  }
  onOpened: if (displayOnly)
    close()
  onClosed: dismissed()
  popupType: Popup.Item
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  width: Math.min(parent ? parent.width - Style.space(24) : Style.space(480), Style.space(560))
  height: Math.min(parent ? parent.height - Style.space(24) : Style.space(520), Style.space(620))
  x: parent ? (parent.width - width) / 2 : 0
  y: parent ? (parent.height - height) / 2 : 0
  padding: Style.space(16)
  background: Aranea.SurfaceCard {
    fillColor: Color.background
    borderSpecOverride: Border.flat(Util.alpha(Color.foreground, 0.16), 1)
  }
  contentItem: ProjectsSidebar {
    id: list
    objectName: 'pickerList'
    rows: picker.rowsFiltered ? picker.rows : picker.rows.filter(function (row) {
      var value = picker.query.trim().toLowerCase()
      return [row.name || '', row.path || '', row.branch || ''].some(function (label) {
        return label.toLowerCase().indexOf(value) >= 0
      })
    })
    selectedId: picker.selectedId
    query: picker.query
    showAddProject: picker.showAddProject
    showCheckoutContext: picker.showCheckoutContext
    searchPlaceholder: picker.searchPlaceholder
    pinningEnabled: picker.pinningEnabled
    navigationEnabled: !picker.displayOnly
    pointerGate: picker.pointerGate
    onQueryChanged: picker.query = query
    onProjectRequested: function (id) {
      picker.select(id)
    }
    onSetupRequested: {
      picker.close()
      picker.setupRequested()
    }
    onPinRequested: function (id, pinned) {
      picker.pinRequested(id, pinned)
    }
  }
}
