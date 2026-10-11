// Primary action with an attached choices menu and two keyboard targets.
// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

FocusScope {
  id: split
  // Label of the default action.
  property alias text: primary.text
  // Shared ActionButton presentation variant.
  property string variant: 'primary'
  // Host-owned immutable menu entries.
  property alias entries: menu.entries
  // Logical menu state for hosts.
  readonly property bool menuOpen: menu.opened
  // Shared pointer settling gate for both buttons and menu feedback.
  property var pointerGate: null
  // Default action request.
  signal clicked
  // Checkbox or action request identified by its stable key.
  signal triggered(string key)

  implicitWidth: primary.implicitWidth + toggle.implicitWidth + Style.space(2)
  implicitHeight: Math.max(Style.space(34), Style.font.body + Style.space(16))
  onEnabledChanged: if (!enabled)
    menu.close()
  Row {
    spacing: Style.space(2)
    Aranea.ActionButton {
      id: primary
      objectName: 'splitPrimary'
      variant: split.variant
      enabled: split.enabled
      implicitHeight: split.implicitHeight
      pointerGate: split.pointerGate
      onClicked: if (split.enabled)
        split.clicked()
    }
    Aranea.ActionButton {
      id: toggle
      objectName: 'splitToggle'
      text: '▾'
      variant: split.variant
      enabled: split.enabled
      implicitHeight: split.implicitHeight
      Accessible.name: 'More open choices'
      pointerGate: split.pointerGate
      onClicked: if (split.enabled)
        menu.opened ? menu.close() : menu.open()
      Keys.onDownPressed: function (event) {
        if (split.enabled) {
          menu.open()
          event.accepted = true
        }
      }
    }
  }
  Aranea.MenuPopup {
    id: menu
    anchors.right: parent.right
    anchors.top: parent.bottom
    anchors.topMargin: Style.space(4)
    pointerGate: split.pointerGate
    onTriggered: function (key) {
      split.triggered(key)
    }
    onClosed: toggle.forceActiveFocus()
  }
}
