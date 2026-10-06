// Responsive category navigation; selecting a destination is read-only.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
  id: navigation
  // Current category shown by the host.
  property string selectedSection: 'appearance'
  // Whether category controls belong above the content.
  property bool compact: false
  // Host pointer movement and layout settling gate.
  property var pointerGate: null
  // Request navigation to a stable category identity.
  signal sectionRequested(string section)
  // Supported category destinations and user-facing labels.
  readonly property var categories: [
    {
      id: 'appearance',
      label: 'Appearance'
    },
    {
      id: 'schedule',
      label: 'Wallpaper schedule'
    },
    {
      id: 'integrations',
      label: 'Integrations'
    },
    {
      id: 'notifications',
      label: 'Notifications'
    }
  ]
  // Request a category change without executing commands.
  function choose(section) {
    sectionRequested(section)
  }
  implicitHeight: compact ? categoryGrid.implicitHeight : Style.space(180)
  GridLayout {
    id: categoryGrid
    anchors.left: parent.left
    anchors.right: parent.right
    columns: navigation.compact ? 2 : 1
    rowSpacing: Style.space(8)
    columnSpacing: Style.space(8)
    Repeater {
      model: navigation.categories
      SettingsButton {
        id: categoryButton
        required property var modelData
        Layout.fillWidth: true
        text: categoryButton.modelData.label
        selected: navigation.selectedSection === categoryButton.modelData.id
        pointerGate: navigation.pointerGate
        onClicked: navigation.choose(categoryButton.modelData.id)
      }
    }
  }
}
