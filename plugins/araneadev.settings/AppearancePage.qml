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
  // Keep a pending choice separate from subsequent owner observations.
  property bool wallpaperDirty: false
  // Whether the inline chooser is expanded; collapsing preserves local choice.
  property bool galleryExpanded: false
  // Current catalog asset, independent of pending choice.
  readonly property var appliedAsset: (page.backendState.wallpapers || []).filter(function (asset) {
    return asset.id === page.appliedId
  })[0] || null
  onAppliedIdChanged: Qt.callLater(function () {
    if (!page.wallpaperDirty)
      page.selectedId = page.appliedId
  })
  Component.onCompleted: if (!wallpaperDirty)
    selectedId = appliedId
  // Ask the persistent controller to perform an explicit operation.
  signal request(string operation, var args)
  // Ask the controller to retry a read, never a mutation.
  signal retryRequested
  // Select a catalog identity without invoking a mutation.
  function selectWallpaper(id) {
    wallpaperDirty = true
    selectedId = id
  }
  // Emit explicit Apply only for an available asset and idle controller.
  function applyWallpaper() {
    if (!displayOnly && !pending && selectedAsset && selectedAsset.available && page.backendState.wallpapersAvailability === 'available')
      request('set wallpaper', [selectedId])
  }
  // Explicitly discard the pending choice using the observed wallpaper.
  function discardWallpaper() {
    wallpaperDirty = false
    selectedId = appliedId
  }
  spacing: Style.space(12)
  SettingsPageHeader {
    Layout.fillWidth: true
    title: 'Appearance'
    description: 'Personalize your wallpaper and desktop motion.'
  }
  SettingsSection {
    Layout.fillWidth: true
    title: 'Wallpaper'
    GridLayout {
      Layout.fillWidth: true
      columns: width < Style.space(360) ? 1 : 2
      columnSpacing: Style.space(12)
      rowSpacing: Style.space(8)
      Rectangle {
        Layout.preferredWidth: Math.min(Style.space(180), parent.width)
        Layout.preferredHeight: Style.space(101)
        color: Util.alpha(Color.foreground, 0.04)
        radius: Style.space(3)
        clip: true
        Image {
          anchors.fill: parent
          anchors.margins: Style.space(2)
          source: page.appliedAsset && page.appliedAsset.available && page.appliedAsset.path ? 'file://' + page.appliedAsset.path : ''
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
        }
      }
      ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: Style.space(8)
        SettingsLabel {
          Layout.fillWidth: true
          objectName: 'wallpaperCurrentName'
          font.pixelSize: Style.font.body
          font.bold: true
          text: page.backendState.wallpapersAvailability === 'available' ? page.appliedId ? (page.appliedAsset ? page.appliedAsset.label : page.appliedId) : page.backendState.wallpaper && page.backendState.wallpaper.availability === 'available' ? 'Custom image' : 'Wallpaper unavailable' : 'Wallpaper catalog: Unavailable'
        }
        SettingsLabel {
          text: 'Current wallpaper'
          opacity: 0.6
        }
        SettingsButton {
          objectName: 'wallpaperChoose'
          text: page.galleryExpanded ? 'Hide chooser' : 'Choose wallpaper'
          pointerGate: page.pointerGate
          onClicked: page.galleryExpanded = !page.galleryExpanded
        }
      }
    }
    GridLayout {
      Layout.fillWidth: true
      visible: page.galleryExpanded
      columns: width < Style.space(420) ? 1 : 2
      rowSpacing: Style.space(8)
      columnSpacing: Style.space(8)
      Repeater {
        model: page.backendState.wallpapers || []
        SettingsButton {
          id: wallpaperOption
          required property var modelData
          objectName: 'wallpaperThumbnail:' + modelData.id
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          Layout.preferredHeight: Style.space(108)
          text: ''
          variant: 'quiet'
          Accessible.name: 'Select ' + modelData.label + ' wallpaper'
          selected: page.selectedId === modelData.id
          pointerGate: page.pointerGate
          onClicked: page.selectWallpaper(modelData.id)
          Image {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(4)
            height: Style.space(74)
            source: wallpaperOption.modelData.available && wallpaperOption.modelData.path ? 'file://' + wallpaperOption.modelData.path : ''
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            clip: true
          }
          SettingsLabel {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(8)
            anchors.rightMargin: Style.space(28)
            text: wallpaperOption.modelData.label + (wallpaperOption.modelData.id === page.appliedId ? ' · Current' : '') + (!wallpaperOption.modelData.available ? ' · Unavailable' : '')
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
          }
          SettingsLabel {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(8)
            text: '✓'
            color: Aranea.DesignTokens.accent
            visible: wallpaperOption.selected
          }
        }
      }
    }
    GridLayout {
      Layout.fillWidth: true
      visible: page.selectedId !== page.appliedId
      columns: page.width < Style.space(220) ? 1 : 2
      columnSpacing: Style.space(8)
      rowSpacing: Style.space(8)
      SettingsButton {
        objectName: 'wallpaperApply'
        Accessible.name: 'Apply wallpaper'
        text: 'Apply'
        variant: 'primary'
        enabled: !page.displayOnly && !page.pending && !!page.selectedAsset && page.selectedAsset.available && page.backendState.wallpapersAvailability === 'available'
        pointerGate: page.pointerGate
        onClicked: page.applyWallpaper()
      }
      SettingsButton {
        objectName: 'wallpaperDiscard'
        Accessible.name: 'Discard wallpaper draft'
        text: 'Discard'
        enabled: !page.displayOnly && !page.pending
        pointerGate: page.pointerGate
        onClicked: page.discardWallpaper()
      }
    }
    SettingsLabel {
      Layout.fillWidth: true
      visible: page.pendingKey === 'wallpaper' || !!page.results.wallpaper
      text: page.pendingKey === 'wallpaper' ? 'Applying…' : page.results.wallpaper || ''
    }
    SettingsLabel {
      objectName: 'wallpaperScheduleNote'
      Layout.fillWidth: true
      visible: !!page.backendState.schedule && page.backendState.schedule.enabled === true
      text: 'Schedule enabled · your wallpaper may change at the next phase.'
      opacity: 0.65
    }
    SettingsLabel {
      Layout.fillWidth: true
      visible: !!page.errors.wallpaper
      text: page.errors.wallpaper || ''
      color: Aranea.DesignTokens.attention
    }
  }
  SettingsSection {
    Layout.fillWidth: true
    title: 'Motion'
    RowLayout {
      Layout.fillWidth: true
      SettingsLabel {
        text: 'Enable animations'
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
      Item {
        Layout.fillWidth: true
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
  }
  SettingsButton {
    text: 'Retry'
    enabled: !page.displayOnly && !page.pending
    pointerGate: page.pointerGate
    visible: page.backendState.wallpapersAvailability !== 'available' || !page.backendState.wallpaper || page.backendState.wallpaper.availability !== 'available' || !page.backendState.motion || page.backendState.motion.availability !== 'available'
    onClicked: page.retryRequested()
  }
}
