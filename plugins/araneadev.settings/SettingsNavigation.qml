// Responsive category navigation; selecting a destination is read-only.
pragma ComponentBehavior: Bound
// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

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
      label: 'Appearance',
      icon: String.fromCodePoint(0xf0303)
    },
    {
      id: 'schedule',
      label: 'Schedule',
      icon: String.fromCodePoint(0xf0150)
    },
    {
      id: 'integrations',
      label: 'Integrations',
      icon: String.fromCodePoint(0xf0c56)
    },
    {
      id: 'notifications',
      label: 'Notifications',
      icon: String.fromCodePoint(0xf009a)
    }
  ]
  // Request a category change without executing commands.
  function choose(section) {
    sectionRequested(section)
  }
  implicitHeight: categoryGrid.implicitHeight
  GridLayout {
    id: categoryGrid
    anchors.left: parent.left
    anchors.right: parent.right
    columns: navigation.compact ? 2 : 1
    rowSpacing: Style.space(4)
    columnSpacing: Style.space(8)
    Repeater {
      model: navigation.categories
      SettingsButton {
        id: categoryButton
        required property var modelData
        Layout.fillWidth: true
        variant: 'navigation'
        text: categoryButton.modelData.label
        selected: navigation.selectedSection === categoryButton.modelData.id
        pointerGate: navigation.pointerGate
        onClicked: navigation.choose(categoryButton.modelData.id)
        Rectangle {
          objectName: 'navigationMarker'
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(2)
          height: Style.space(16)
          color: Aranea.DesignTokens.accent
          visible: categoryButton.selected
        }
        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)
          Text {
            objectName: 'navigationIcon'
            text: categoryButton.modelData.icon
            textFormat: Text.PlainText
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            color: categoryButton.selected ? Aranea.DesignTokens.accent : Color.foreground
          }
          SettingsLabel {
            Layout.fillWidth: true
            text: categoryButton.text
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
