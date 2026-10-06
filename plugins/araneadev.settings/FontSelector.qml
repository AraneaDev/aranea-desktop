// Compact installed-family chooser; selection only changes the local draft.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

ColumnLayout {
  id: selector
  // Accessible role caption.
  property string title: ''
  // Installed family catalog for this font role.
  property var families: []
  // Selected draft; empty follows the desktop default.
  property string family: ''
  // Search text and expanded inline chooser state.
  property string query: ''
  // Whether the inline installed-font list is expanded.
  property bool expanded: false
  // Host movement/settling gate for pointer actions.
  property var pointerGate: null
  // Matching installed families, plus a discoverable default choice.
  readonly property var filteredFamilies: [''].concat(families).filter(function (value) {
    return (value || 'Default').toLowerCase().indexOf(selector.query.toLowerCase()) >= 0
  })
  // A chosen family never writes preferences by itself.
  signal chosen(string family)
  // Guard keyboard and pointer selection with the same installed catalog.
  function choose(value) {
    if (!enabled || (value !== '' && families.indexOf(value) < 0))
      return
    chosen(value)
    expanded = false
    query = ''
    chooserButton.forceActiveFocus()
  }
  spacing: Style.space(4)
  SettingsLabel {
    Layout.fillWidth: true
    text: selector.title
  }
  SettingsButton {
    id: chooserButton
    Layout.fillWidth: true
    text: (selector.family || 'Default') + '  ▾'
    Accessible.name: selector.title + ': ' + (selector.family || 'Default')
    pointerGate: selector.pointerGate
    onClicked: {
      selector.expanded = !selector.expanded
      if (selector.expanded)
        search.forceActiveFocus()
    }
  }
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: Style.space(28)
    visible: selector.expanded
    radius: Style.space(3)
    color: Util.alpha(Color.foreground, 0.04)
    border.width: 1
    border.color: search.activeFocus ? Aranea.DesignTokens.accent : Util.alpha(Color.foreground, 0.15)
    TextInput {
      id: search
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      verticalAlignment: TextInput.AlignVCenter
      text: selector.query
      onTextEdited: selector.query = text
      color: Color.foreground
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.caption
      selectByMouse: true
      activeFocusOnTab: true
      Accessible.name: 'Search ' + selector.title.toLowerCase()
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
          choices.currentIndex = Math.max(0, Math.min(choices.count - 1, choices.currentIndex + (event.key === Qt.Key_Down ? 1 : -1)))
          choices.positionViewAtIndex(choices.currentIndex, ListView.Contain)
          event.accepted = true
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && choices.count > 0) {
          selector.choose(selector.filteredFamilies[Math.max(0, choices.currentIndex)])
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          selector.expanded = false
          event.accepted = true
        }
      }
    }
    SettingsLabel {
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      verticalAlignment: Text.AlignVCenter
      text: 'Search installed fonts…'
      visible: !search.text && !search.activeFocus
      opacity: 0.5
    }
  }
  ListView {
    id: choices
    Layout.fillWidth: true
    Layout.preferredHeight: Math.min(count, 4) * Style.space(28)
    visible: selector.expanded
    clip: true
    model: selector.filteredFamilies
    currentIndex: 0
    onModelChanged: currentIndex = 0
    delegate: SettingsButton {
      required property string modelData
      required property int index
      width: choices.width
      height: Style.space(28)
      text: modelData || 'Default'
      selected: index === choices.currentIndex
      pointerGate: selector.pointerGate
      onClicked: selector.choose(modelData)
    }
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: selector.expanded && choices.count === 0
    text: 'No matching installed fonts'
    opacity: 0.65
  }
}
