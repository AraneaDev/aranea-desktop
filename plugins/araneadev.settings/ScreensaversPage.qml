// Scene and timing drafts have independent explicit save boundaries.
// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import "../araneadev.shared" as Aranea

ColumnLayout {
  id: page
  objectName: 'screensaversPage'
  // Observed owners and persistent operation feedback, never executable text.
  property var backendState: ({})
  // Latest persistent scene, timing and preview outcomes.
  property var results: ({})
  // Actionable operation errors retained across owner reads.
  property var errors: ({})
  // All explicit controls share the host's pending, capture and pointer guards.
  property bool displayOnly: false
  // Whether an explicit owner operation is running.
  property bool pending: false
  // Stable identity of the operation currently running.
  property string pendingKey: ''
  // Shared movement and layout settling guard for pointer actions.
  property var pointerGate: null
  // Remember the single choice even while shuffle clears the card highlight.
  property string selectedId: ''
  // Local single or shuffle mode, independent of persisted choice.
  property string modeDraft: 'single'
  // Retain scene edits until matching explicit Apply or Discard.
  property bool sceneDirty: false
  // Retain exact seconds independently of each field's editable minutes text.
  property var timingDraft: ({
      screensaverSeconds: null,
      lockSeconds: null
    })
  // Editable whole-minute text; exact non-minute seconds stay in timingDraft.
  property var timingText: ({
      screensaverSeconds: '',
      lockSeconds: ''
    })
  // Retain timing edits and failures independently of scene edits.
  property bool timingDirty: false
  // Partial authoritative screensaver owner snapshot.
  readonly property var saver: backendState.screensaver || ({})
  // Configured inactivity deadlines and observed pause indicators.
  readonly property var idle: saver.idle || ({})
  // Trusted catalog projection containing display data and stable IDs.
  readonly property var choices: saver.choices || []
  // Remembered single scene, including unavailable or unknown selections.
  readonly property var choice: choices.filter(function (value) {
    return value.id === page.selectedId
  })[0] || null
  // Capture and pending guards shared by every mutation path.
  readonly property bool editable: !displayOnly && !pending
  // Whether the catalog is available for selecting a scene.
  readonly property bool sceneAvailable: saver.catalogAvailable === true
  // Both exact-second drafts fit the backend integer range.
  readonly property bool timingValid: validSeconds(timingDraft.screensaverSeconds) && validSeconds(timingDraft.lockSeconds)
  // Enabled lock deadline must follow enabled screensaver deadline.
  readonly property bool timingOrderValid: !timingDraft.screensaverSeconds || !timingDraft.lockSeconds || timingDraft.lockSeconds > timingDraft.screensaverSeconds
  // Only controller-owned explicit actions cross the process boundary.
  signal request(string operation, var args)
  // Ask the persistent controller for a fresh read only.
  signal retryRequested
  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl('i18n')
  }
  // Validate configured seconds without rounding existing values.
  function validSeconds(value) {
    return typeof value === 'number' && isFinite(value) && Math.floor(value) === value && value >= 0 && value <= 86400
  }
  // Show configured whole minutes, exact seconds or explicit Disabled.
  function duration(value) {
    return !validSeconds(value) ? strings.t('screensavers.unavailable') : value === 0 ? strings.t('screensavers.disabled') : value % 60 === 0 ? strings.t('screensavers.minuteValue').arg(value / 60) : strings.t('screensavers.secondValue').arg(value)
  }
  // Translate persistent operation outcomes while preserving backend diagnostics.
  function feedback(key) {
    if (pendingKey === key && pending)
      return strings.t('screensavers.applying')
    var ids = {
      'Saved': 'saved',
      'Save not confirmed': 'saveUnconfirmed',
      'Preview accepted': 'previewAccepted',
      'Stock preview delegated': 'stockDelegated',
      'Preview not confirmed': 'previewUnconfirmed',
      'Timing saved': 'timingSaved',
      'Saved · reload failed': 'reloadFailed',
      'Failed': 'failed'
    }
    return ids[results[key]] ? strings.t('screensavers.' + ids[results[key]]) : results[key] || ''
  }
  // Clean drafts follow readback. Dirty drafts survive failures and unrelated reads.
  function syncScene() {
    if (!sceneDirty) {
      selectedId = typeof saver.selectedId === 'string' ? saver.selectedId : ''
      modeDraft = saver.mode === 'shuffle' ? 'shuffle' : 'single'
    }
  }
  // Adopt configured seconds only when the timing draft is clean.
  function syncTiming() {
    if (timingDirty)
      return
    timingDraft = {
      screensaverSeconds: idle.screensaverSeconds === undefined ? null : idle.screensaverSeconds,
      lockSeconds: idle.lockSeconds === undefined ? null : idle.lockSeconds
    }
    var text = {};
    ['screensaverSeconds', 'lockSeconds'].forEach(function (key) {
      var value = page.timingDraft[key]
      text[key] = page.validSeconds(value) && value > 0 && value % 60 === 0 ? String(value / 60) : ''
    })
    timingText = text
  }
  // Select a catalog scene locally and return to single mode.
  function selectScene(id) {
    if (!editable || !sceneAvailable || !choices.some(function (value) {
      return value.id === id && value.available === true
    }))
      return
    selectedId = id
    modeDraft = 'single'
    sceneDirty = true
  }
  // Toggle the local mode while retaining the remembered single scene.
  function toggleShuffle() {
    if (!editable || !sceneAvailable)
      return
    modeDraft = modeDraft === 'shuffle' ? 'single' : 'shuffle'
    sceneDirty = true
  }
  // Submit only an available scene and its explicit local mode.
  function applyScene() {
    if (editable && sceneAvailable && sceneDirty && choice && choice.available === true)
      request('configure screensaver', [selectedId, modeDraft])
  }
  // Preview the remembered available scene without saving either draft.
  function previewScene() {
    if (editable && sceneAvailable && choice && choice.available === true)
      request('preview screensaver', [selectedId])
  }
  // Discard only local scene and mode edits.
  function discardScene() {
    if (!editable)
      return
    sceneDirty = false
    syncScene()
  }
  // A field changes only after an actual edit or explicit Disabled selection.
  function setTimingDraft(key, value, disabled) {
    if (!editable || ['screensaverSeconds', 'lockSeconds'].indexOf(key) < 0)
      return
    var next = Object.assign({}, timingDraft)
    next[key] = disabled === true ? 0 : /^[1-9][0-9]*$/.test(value) && Number(value) <= 1440 ? Number(value) * 60 : null
    timingDraft = next
    var text = Object.assign({}, timingText)
    if (!disabled)
      text[key] = value
    timingText = text
    timingDirty = true
  }
  // Submit exact seconds after explicit duration validation.
  function applyTiming() {
    if (editable && timingDirty && timingValid && timingOrderValid)
      request('configure screensaver-timing', [String(timingDraft.screensaverSeconds), String(timingDraft.lockSeconds)])
  }
  // Discard only timing edits and adopt configured deadlines.
  function discardTiming() {
    if (!editable)
      return
    timingDirty = false
    syncTiming()
  }
  // A completion acknowledges only the exact submitted draft and fresh owner values.
  function acceptSaved(operation, args) {
    if (operation === 'configure screensaver' && selectedId === args[0] && modeDraft === args[1] && saver.selectedId === args[0] && saver.mode === args[1]) {
      sceneDirty = false
      syncScene()
    } else if (operation === 'configure screensaver-timing' && timingDraft.screensaverSeconds === Number(args[0]) && timingDraft.lockSeconds === Number(args[1]) && idle.screensaverSeconds === Number(args[0]) && idle.lockSeconds === Number(args[1])) {
      timingDirty = false
      syncTiming()
    }
  }
  // Capture resets presentation only after the controller installs inert observations.
  function resetDrafts() {
    sceneDirty = false
    timingDirty = false
    syncScene()
    syncTiming()
  }
  onSaverChanged: syncScene()
  onIdleChanged: syncTiming()
  Component.onCompleted: resetDrafts()
  spacing: Style.space(10)
  SettingsPageHeader {
    Layout.fillWidth: true
    title: strings.t('screensavers.title')
    description: strings.t('screensavers.description')
  }
  SettingsLabel {
    Layout.fillWidth: true
    objectName: 'screensaverCurrent'
    text: page.saver.mode === 'shuffle' ? strings.t('screensavers.shuffleCurrent') : strings.t('screensavers.current').arg((page.choices.filter(function (value) {
        return value.id === page.saver.selectedId
      })[0] || {}).label || strings.t('screensavers.unknown'))
    opacity: 0.75
  }
  GridLayout {
    objectName: 'screensaverGallery'
    Layout.fillWidth: true
    columns: width >= Style.space(400) ? 3 : width >= Style.space(250) ? 2 : 1
    columnSpacing: Style.space(8)
    rowSpacing: Style.space(8)
    Repeater {
      model: page.choices
      SettingsButton {
        id: tile
        required property var modelData
        objectName: 'screensaverChoice:' + modelData.id
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredHeight: width * 9 / 16 + Style.space(42)
        selected: page.modeDraft === 'single' && page.selectedId === modelData.id
        enabled: page.editable && page.sceneAvailable && modelData.available === true
        Accessible.name: modelData.label || modelData.id
        pointerGate: page.pointerGate
        onClicked: page.selectScene(modelData.id)
        Image {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.space(4)
          height: width * 9 / 16
          source: tile.modelData.thumbnail ? 'file://' + tile.modelData.thumbnail : Aranea.RuntimePaths.glyphUrl
          fillMode: tile.modelData.thumbnail ? Image.PreserveAspectCrop : Image.PreserveAspectFit
          opacity: tile.modelData.thumbnail ? 1 : 0.45
          asynchronous: true
          clip: true
        }
        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(6)
          SettingsLabel {
            width: parent.width
            text: tile.modelData.label || tile.modelData.id
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            font.bold: tile.selected
          }
          SettingsLabel {
            width: parent.width
            text: tile.modelData.available !== true ? strings.t('screensavers.unavailable') : page.saver.mode === 'single' && page.saver.selectedId === tile.modelData.id ? strings.t('screensavers.currentMarker') : tile.modelData.renderer || ''
            font.pixelSize: Style.font.caption
            opacity: 0.65
          }
        }
      }
    }
  }
  RowLayout {
    Layout.fillWidth: true
    SettingsToggle {
      objectName: 'screensaverShuffle'
      checked: page.modeDraft === 'shuffle'
      enabled: page.editable && page.sceneAvailable
      Accessible.name: strings.t('screensavers.shuffle')
      pointerGate: page.pointerGate
      onToggled: page.toggleShuffle()
    }
    SettingsLabel {
      Layout.fillWidth: true
      text: strings.t('screensavers.shuffle')
    }
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: page.modeDraft === 'shuffle' || !!(page.choice && page.choice.description)
    text: page.modeDraft === 'shuffle' ? strings.t('screensavers.shuffleHelp') : page.choice ? page.choice.description || '' : ''
    opacity: 0.65
  }
  Flow {
    Layout.fillWidth: true
    spacing: Style.space(8)
    SettingsButton {
      objectName: 'screensaverPreview'
      text: strings.t('screensavers.preview')
      enabled: page.editable && page.sceneAvailable && !!page.choice && page.choice.available === true
      pointerGate: page.pointerGate
      onClicked: page.previewScene()
    }
    SettingsButton {
      objectName: 'screensaverApply'
      text: strings.t('screensavers.apply')
      variant: 'primary'
      enabled: page.editable && page.sceneDirty && page.sceneAvailable && !!page.choice && page.choice.available === true
      pointerGate: page.pointerGate
      onClicked: page.applyScene()
    }
    SettingsButton {
      objectName: 'screensaverDiscard'
      text: strings.t('screensavers.discard')
      enabled: page.editable && page.sceneDirty
      pointerGate: page.pointerGate
      onClicked: page.discardScene()
    }
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: strings.t('screensavers.previewHelp')
    font.pixelSize: Style.font.caption
    opacity: 0.6
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !!page.feedback('screensaver') || !!page.feedback('screensaver-preview')
    text: [page.feedback('screensaver'), page.feedback('screensaver-preview')].filter(function (value) {
      return !!value
    }).join(' · ')
    opacity: 0.75
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !!page.errors.screensaver || !!page.errors['screensaver-preview'] || !!page.saver.error
    text: page.errors.screensaver || page.errors['screensaver-preview'] || page.saver.error || ''
    color: Aranea.DesignTokens.attention
  }
  SettingsLabel {
    objectName: 'screensaverRuntimeError'
    Layout.fillWidth: true
    visible: !!page.saver.session && !!page.saver.session.error
    text: page.saver.session ? page.saver.session.error || '' : ''
    color: Aranea.DesignTokens.attention
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !!page.choice && page.choice.available !== true
    text: page.choice ? page.choice.reason || strings.t('screensavers.unavailable') : ''
    color: Aranea.DesignTokens.attention
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !!page.saver.integration && page.saver.integration.reachable === false
    text: strings.t('screensavers.automaticMissing')
    font.pixelSize: Style.font.caption
    opacity: 0.6
  }
  SettingsSection {
    Layout.fillWidth: true
    title: strings.t('screensavers.timing')
    SettingsLabel {
      Layout.fillWidth: true
      text: strings.t('screensavers.timingHelp')
      font.pixelSize: Style.font.caption
      opacity: 0.7
    }
    GridLayout {
      Layout.fillWidth: true
      columns: width >= Style.space(360) ? 2 : 1
      columnSpacing: Style.space(12)
      rowSpacing: Style.space(8)
      Repeater {
        model: ['screensaverSeconds', 'lockSeconds']
        ColumnLayout {
          id: durationField
          required property string modelData
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          spacing: Style.space(4)
          SettingsLabel {
            Layout.fillWidth: true
            text: strings.t(durationField.modelData === 'screensaverSeconds' ? 'screensavers.saverAfter' : 'screensavers.lockAfter')
            font.bold: true
          }
          RowLayout {
            Layout.fillWidth: true
            Rectangle {
              Layout.fillWidth: true
              Layout.minimumWidth: Style.space(40)
              Layout.preferredHeight: Style.space(28)
              color: Util.alpha(Commons.Color.foreground, 0.04)
              border.width: 1
              border.color: Util.alpha(Commons.Color.foreground, 0.18)
              radius: Style.space(3)
              Aranea.FocusFrame {
                anchors.fill: parent
                focused: minutes.activeFocus
              }
              TextInput {
                id: minutes
                objectName: 'screensaverMinutes:' + durationField.modelData
                anchors.fill: parent
                anchors.margins: Style.space(5)
                verticalAlignment: TextInput.AlignVCenter
                text: page.timingText[durationField.modelData]
                color: Commons.Color.foreground
                font.family: Aranea.Typography.technicalFamily
                font.pixelSize: Style.font.body
                enabled: page.editable && page.timingDraft[durationField.modelData] !== 0
                selectByMouse: true
                activeFocusOnTab: true
                maximumLength: 5
                Accessible.name: strings.t('screensavers.minutes')
                onTextEdited: page.setTimingDraft(durationField.modelData, text)
              }
            }
            SettingsButton {
              objectName: 'screensaverDisabled:' + durationField.modelData
              text: strings.t('screensavers.disabled')
              selected: page.timingDraft[durationField.modelData] === 0
              enabled: page.editable
              pointerGate: page.pointerGate
              onClicked: page.setTimingDraft(durationField.modelData, page.timingText[durationField.modelData], page.timingDraft[durationField.modelData] !== 0)
            }
          }
          SettingsLabel {
            Layout.fillWidth: true
            text: strings.t('screensavers.minutes')
            font.pixelSize: Style.font.caption
            opacity: 0.6
          }
          SettingsLabel {
            Layout.fillWidth: true
            text: strings.t('screensavers.configured').arg(page.duration(page.idle[durationField.modelData]))
            font.pixelSize: Style.font.caption
            opacity: 0.75
          }
        }
      }
    }
    SettingsLabel {
      Layout.fillWidth: true
      visible: page.timingDirty && (!page.timingValid || !page.timingOrderValid)
      text: strings.t(!page.timingValid ? 'screensavers.invalidTiming' : 'screensavers.invalidOrder')
      color: Aranea.DesignTokens.attention
    }
    Flow {
      Layout.fillWidth: true
      spacing: Style.space(8)
      SettingsButton {
        objectName: 'screensaverTimingApply'
        text: strings.t('screensavers.applyTiming')
        variant: 'primary'
        enabled: page.editable && page.timingDirty && page.timingValid && page.timingOrderValid
        pointerGate: page.pointerGate
        onClicked: page.applyTiming()
      }
      SettingsButton {
        objectName: 'screensaverTimingDiscard'
        text: strings.t('screensavers.discardTiming')
        enabled: page.editable && page.timingDirty
        pointerGate: page.pointerGate
        onClicked: page.discardTiming()
      }
    }
    SettingsLabel {
      Layout.fillWidth: true
      visible: !!page.feedback('screensaver-timing')
      text: page.feedback('screensaver-timing')
      opacity: 0.75
    }
    SettingsLabel {
      Layout.fillWidth: true
      visible: !!page.errors['screensaver-timing'] || !!page.idle.error
      text: page.errors['screensaver-timing'] || page.idle.error || ''
      color: Aranea.DesignTokens.attention
    }
    SettingsLabel {
      Layout.fillWidth: true
      visible: page.idle.stayAwake === true || page.idle.screensaverOff === true
      text: [page.idle.stayAwake === true ? strings.t('screensavers.stayAwake') : '', page.idle.screensaverOff === true ? strings.t('screensavers.saverOff') : ''].filter(function (value) {
        return !!value
      }).join(' ')
      opacity: 0.75
    }
  }
  SettingsButton {
    text: strings.t('screensavers.retry')
    visible: !page.sceneAvailable || !!page.idle.error
    enabled: page.editable
    pointerGate: page.pointerGate
    onClicked: if (page.editable)
      page.retryRequested()
  }
}
