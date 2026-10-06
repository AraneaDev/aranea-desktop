// Wallpaper selection and motion controls; mutations require explicit actions.
// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

ColumnLayout {
  id: page
  // Current backend snapshot; partial sections retain their own availability.
  property var backendState: ({})
  // Whether controls show inert capture fixtures and refuse changes.
  property bool displayOnly: false
  // Whether a settings mutation is in flight.
  property bool pending: false
  // Stable key of the affected control while applying.
  property string pendingKey: ''
  // Latest per-control application outcomes.
  property var results: ({})
  // Per-control mutation errors.
  property var errors: ({})
  // Host pointer movement and layout settling gate.
  property var pointerGate: null
  // Local wallpaper selection, independent of the applied desktop image.
  property string selectedId: ''
  // Wallpaper identity observed from the desktop owner.
  readonly property string appliedId: page.backendState.wallpaper && page.backendState.wallpaper.activeId || ''
  // Catalog entry for the local selection, including asset availability.
  readonly property var selectedAsset: (page.backendState.wallpapers || []).filter(function (asset) {
    return asset.id === page.selectedId
  })[0] || null
  // Ask the persistent controller to perform an explicit operation.
  signal request(string operation, var args)
  // Ask the controller to retry a read, never a mutation.
  signal retryRequested
  // Select a catalog identity without invoking a mutation.
  function selectWallpaper(id) {
    selectedId = id
  }
  // Emit explicit Apply only for an available asset and idle controller.
  function applyWallpaper() {
    if (!displayOnly && !pending && selectedAsset && selectedAsset.available && page.backendState.wallpapersAvailability === 'available')
      request('set wallpaper', [selectedId])
  }
  spacing: Style.space(16)
  SettingsLabel {
    Layout.fillWidth: true
    text: 'Appearance'
    font.pixelSize: Style.font.title
    font.bold: true
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: 'Choose a wallpaper, then Apply it to your desktop.'
    opacity: 0.65
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: page.backendState.wallpapersAvailability === 'available' ? page.appliedId ? 'Current wallpaper: ' + page.appliedId : page.backendState.wallpaper && page.backendState.wallpaper.availability === 'available' ? 'Current wallpaper: custom image' : 'Current wallpaper: Unavailable' : 'Wallpaper catalog: Unavailable'
  }
  GridLayout {
    Layout.fillWidth: true
    columns: page.width < Style.space(420) ? 1 : 2
    rowSpacing: Style.space(8)
    columnSpacing: Style.space(8)
    Repeater {
      model: page.backendState.wallpapers || []
      ColumnLayout {
        id: wallpaperOption
        required property var modelData
        Layout.fillWidth: true
        spacing: Style.space(4)
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(105)
          color: Util.alpha(Color.foreground, 0.04)
          border.color: page.selectedId === wallpaperOption.modelData.id ? Aranea.DesignTokens.accent : Util.alpha(Color.foreground, 0.12)
          border.width: 1
          Image {
            anchors.fill: parent
            anchors.margins: 1
            source: wallpaperOption.modelData.path ? 'file://' + wallpaperOption.modelData.path : ''
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: wallpaperOption.modelData.available
            clip: true
          }
          SettingsLabel {
            anchors.centerIn: parent
            visible: !wallpaperOption.modelData.available
            text: 'Unavailable'
            opacity: 0.65
          }
        }
        SettingsButton {
          Layout.fillWidth: true
          text: wallpaperOption.modelData.label + (wallpaperOption.modelData.id === page.appliedId ? ' · Current' : '')
          selected: page.selectedId === wallpaperOption.modelData.id
          pointerGate: page.pointerGate
          onClicked: page.selectWallpaper(wallpaperOption.modelData.id)
        }
      }
    }
  }
  RowLayout {
    Layout.fillWidth: true
    SettingsButton {
      objectName: 'wallpaperApply'
      text: 'Apply wallpaper'
      selected: true
      enabled: !page.displayOnly && !page.pending && !!page.selectedAsset && page.selectedAsset.available && page.backendState.wallpapersAvailability === 'available'
      pointerGate: page.pointerGate
      onClicked: page.applyWallpaper()
    }
    SettingsLabel {
      Layout.fillWidth: true
      text: page.pendingKey === 'wallpaper' ? 'Applying…' : page.results.wallpaper || ''
    }
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !!page.errors.wallpaper
    text: page.errors.wallpaper || ''
    color: Aranea.DesignTokens.attention
  }
  Rectangle {
    Layout.fillWidth: true
    implicitHeight: 1
    color: Util.alpha(Color.foreground, 0.12)
  }
  RowLayout {
    Layout.fillWidth: true
    SettingsLabel {
      Layout.fillWidth: true
      text: 'Motion'
      font.bold: true
    }
    SettingsToggle {
      objectName: 'motionToggle'
      Accessible.name: 'Motion'
      checked: !!page.backendState.motion && page.backendState.motion.configured === 'on'
      enabled: !page.displayOnly && !page.pending && !!page.backendState.motion && page.backendState.motion.availability === 'available'
      busy: page.pendingKey === 'motion'
      pointerGate: page.pointerGate
      onToggled: page.request('set motion', [checked ? 'off' : 'on'])
    }
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: page.pendingKey === 'motion' ? 'Applying…' : page.results.motion || (page.backendState.motion && page.backendState.motion.availability === 'available' ? page.backendState.motion.application === 'deferred' ? 'Saved · application deferred' : page.backendState.motion.application === 'unavailable' ? 'Live motion state unavailable' : 'Use desktop and panel animations.' : 'Motion: Unavailable')
    opacity: 0.65
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !!page.errors.motion
    text: page.errors.motion || ''
    color: Aranea.DesignTokens.attention
  }
  SettingsButton {
    text: 'Retry'
    enabled: !page.displayOnly && !page.pending
    pointerGate: page.pointerGate
    visible: page.backendState.wallpapersAvailability !== 'available' || !page.backendState.wallpaper || page.backendState.wallpaper.availability !== 'available' || !page.backendState.motion || page.backendState.motion.availability !== 'available'
    onClicked: page.retryRequested()
  }
}
