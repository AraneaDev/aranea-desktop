// One daily entry with an explicit thumbnail-backed wallpaper choice.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import "../araneadev.shared" as Aranea

ColumnLayout {
  id: row
  // Daily local-clock time and stable catalog image ID.
  property var entry: ({
      time: '',
      wallpaper: ''
    })
  // Human-readable position in the editable list.
  property int rowNumber: 1
  // Registered wallpapers, including unavailable assets.
  property var catalog: []
  // Guard all editing during captures and pending requests.
  property bool editable: false
  // At least one daily entry must remain.
  property bool removable: false
  // Actionable validation for this row.
  property string error: ''
  // Host movement gate for pointer activation.
  property var pointerGate: null
  // Expand only this entry's image choices.
  property bool choosing: false
  // The selected asset provides a title and preview.
  readonly property var asset: catalog.filter(function (value) {
    return value.id === row.entry.wallpaper
  })[0] || null
  // Reports a local-clock draft edit.
  signal timeEdited(string value)
  // Reports a selected stable wallpaper ID.
  signal wallpaperSelected(string value)
  // Requests removal while preserving the minimum entry count.
  signal removeRequested
  spacing: Style.space(8)
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(8)
    Rectangle {
      Layout.preferredWidth: Style.space(72)
      Layout.preferredHeight: Style.space(32)
      color: Util.alpha(Commons.Color.foreground, 0.04)
      radius: Style.space(3)
      border.width: 1
      border.color: Util.alpha(Commons.Color.foreground, 0.15)
      Aranea.FocusFrame {
        anchors.fill: parent
        focused: field.activeFocus
      }
      TextInput {
        id: field
        objectName: 'scheduleTime:' + row.rowNumber
        anchors.fill: parent
        anchors.margins: Style.space(6)
        verticalAlignment: TextInput.AlignVCenter
        text: row.entry.time
        color: Commons.Color.foreground
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: Style.font.body
        enabled: row.editable
        activeFocusOnTab: true
        selectByMouse: true
        maximumLength: 5
        Accessible.name: 'Entry ' + row.rowNumber + ' time'
        onTextEdited: if (row.editable)
          row.timeEdited(text)
      }
    }
    Image {
      Layout.preferredWidth: Style.space(48)
      Layout.preferredHeight: Style.space(28)
      source: row.asset && row.asset.available && row.asset.path ? 'file://' + row.asset.path : ''
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      clip: true
    }
    SettingsButton {
      objectName: 'scheduleWallpaper:' + row.rowNumber
      Layout.fillWidth: true
      Layout.minimumWidth: 0
      text: row.asset ? (row.asset.label || row.asset.id) + (!row.asset.available ? ' · Unavailable' : '') : 'Choose wallpaper'
      Accessible.name: 'Choose wallpaper for entry ' + row.rowNumber
      enabled: row.editable
      pointerGate: row.pointerGate
      onClicked: if (row.editable)
        row.choosing = !row.choosing
    }
    SettingsButton {
      objectName: 'scheduleRemove:' + row.rowNumber
      text: 'Remove'
      Accessible.name: 'Remove entry ' + row.rowNumber
      enabled: row.editable && row.removable
      pointerGate: row.pointerGate
      onClicked: if (row.editable && row.removable)
        row.removeRequested()
    }
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !!row.error
    text: row.error
    color: Aranea.DesignTokens.attention
  }
  GridLayout {
    Layout.fillWidth: true
    visible: row.choosing
    columns: width >= Style.space(420) ? 3 : width >= Style.space(260) ? 2 : 1
    columnSpacing: Style.space(8)
    rowSpacing: Style.space(8)
    Repeater {
      model: row.catalog
      SettingsButton {
        id: option
        required property var modelData
        objectName: 'scheduleChoice:' + row.rowNumber + ':' + modelData.id
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredHeight: Math.max(Style.space(72), width * 9 / 16 + Style.space(28))
        text: ''
        selected: row.entry.wallpaper === modelData.id
        enabled: row.editable && modelData.available === true
        Accessible.name: 'Select ' + (modelData.label || modelData.id)
        pointerGate: row.pointerGate
        onClicked: if (row.editable && modelData.available === true) {
          row.wallpaperSelected(modelData.id)
          row.choosing = false
        }
        Image {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(4)
          height: Math.max(0, width * 9 / 16)
          source: option.modelData.available && option.modelData.path ? 'file://' + option.modelData.path : ''
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          clip: true
        }
        SettingsLabel {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(6)
          text: (option.modelData.label || option.modelData.id) + (!option.modelData.available ? ' · Unavailable' : '')
          wrapMode: Text.NoWrap
          elide: Text.ElideRight
        }
      }
    }
  }
}
