// Focused display scaling drafts delegate exact decimals to the existing controller.
// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea
import "SettingsLogic.js" as Logic

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
  // Current focused-display observation from the compositor, never a default.
  readonly property var display: page.backendState.display || ({})
  // Whether this focused display and its scaling owner can accept changes.
  readonly property bool displayAvailable: display.availability === 'available'
  // Exact locally typed fraction, retained after owner adjustment and reopen.
  property string scaleDraft: ''
  // Whether the user has edited the local scale entry.
  property bool scaleDirty: false
  // Typed decimal validation; never restrict to the owner's presets.
  readonly property var scaleValidation: Logic.validateScale(scaleDraft)
  // Adopt an owner observation only before the user edits the scale.
  onDisplayChanged: if (!scaleDirty)
    scaleDraft = typeof display.scale === 'number' ? String(display.scale) : ''
  // Change a local scale draft without dispatching commands.
  function setScaleDraft(value) {
    scaleDirty = true
    scaleDraft = value
  }
  // Apply the exact decimal through the controller's focused-display guard.
  function applyScale() {
    if (!displayOnly && !pending && displayAvailable && scaleValidation.ok)
      request('set display-scale', [scaleDraft])
  }
  // Restore the current owner observation only on explicit Discard.
  function discardScale() {
    scaleDirty = false
    scaleDraft = typeof display.scale === 'number' ? String(display.scale) : ''
  }
  // Whether the longer persistence explanation is expanded.
  property bool detailsExpanded: false
  // Ask the persistent controller to perform an explicit operation.
  signal request(string operation, var args)
  // Ask the controller to retry a read, never a mutation.
  signal retryRequested
  spacing: Style.space(12)
  SettingsPageHeader {
    Layout.fillWidth: true
    title: 'Display'
    description: 'Choose a comfortable size for your desktop.'
  }
  SettingsSection {
    Layout.fillWidth: true
    title: 'Scale'
    SettingsLabel {
      objectName: 'displayObservation'
      technical: true
      Layout.fillWidth: true
      text: page.display.monitor ? page.display.monitor + (page.display.width && page.display.height ? ' · ' + page.display.width + ' × ' + page.display.height : '') + ' · Current scale: ' + page.display.scale : 'Focused display: Unavailable'
      opacity: 0.7
    }
    Rectangle {
      Layout.preferredWidth: Math.min(Style.space(248), parent.width)
      Layout.preferredHeight: presetGrid.implicitHeight + Style.space(8)
      color: Util.alpha(Color.foreground, 0.025)
      radius: Style.space(3)
      border.width: 1
      border.color: Util.alpha(Color.foreground, 0.08)
      GridLayout {
        id: presetGrid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(4)
        columns: parent.width < Style.space(230) ? 2 : 4
        columnSpacing: Style.space(2)
        rowSpacing: Style.space(2)
        Repeater {
          model: ['2', '2.5', '2.667', '3']
          SettingsButton {
            required property string modelData
            objectName: 'displayScalePreset'
            Layout.fillWidth: true
            variant: 'segment'
            text: modelData + '×'
            selected: page.scaleDraft === modelData
            enabled: page.displayAvailable && !page.displayOnly && !page.pending
            pointerGate: page.pointerGate
            onClicked: page.setScaleDraft(modelData)
          }
        }
      }
    }

    GridLayout {
      Layout.preferredWidth: Math.min(implicitWidth, parent.width)
      columns: parent.width < Style.space(280) ? 1 : 3
      columnSpacing: Style.space(8)
      rowSpacing: Style.space(8)
      Rectangle {
        Layout.preferredWidth: Math.min(Style.space(136), parent.width)
        Layout.preferredHeight: Style.space(28)
        radius: Style.space(3)
        color: Util.alpha(Color.foreground, 0.04)
        border.width: 1
        border.color: scaleField.activeFocus ? Aranea.DesignTokens.accent : Util.alpha(Color.foreground, 0.15)
        TextInput {
          id: scaleField
          objectName: 'displayScaleInput'
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          verticalAlignment: TextInput.AlignVCenter
          text: page.scaleDraft
          color: Color.foreground
          font.family: Aranea.Typography.technicalFamily
          font.pixelSize: Style.font.body
          enabled: page.displayAvailable && !page.displayOnly && !page.pending
          activeFocusOnTab: true
          selectByMouse: true
          inputMethodHints: Qt.ImhFormattedNumbersOnly
          Accessible.name: 'Custom display scale from 1 to 4'
          onTextEdited: page.setScaleDraft(text)
        }
      }
      SettingsButton {
        objectName: 'displayScaleApply'
        Accessible.name: 'Apply display scale'
        text: 'Apply'
        variant: 'primary'
        enabled: page.displayAvailable && !page.displayOnly && !page.pending && page.scaleValidation.ok
        pointerGate: page.pointerGate
        onClicked: page.applyScale()
      }
      SettingsButton {
        objectName: 'displayScaleDiscard'
        Accessible.name: 'Discard display scale draft'
        text: 'Discard'
        enabled: !page.displayOnly && !page.pending && page.scaleDirty
        pointerGate: page.pointerGate
        onClicked: page.discardScale()
      }
    }
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: page.scaleDirty && !page.scaleValidation.ok ? page.scaleValidation.message : !page.displayAvailable ? 'Scaling unavailable' : page.display.persistenceSupport === 'supported' ? 'Saving supported' : page.display.persistenceSupport === 'unsupported' ? 'Session only' : 'Persistence unavailable'
    color: page.scaleDirty && !page.scaleValidation.ok ? Aranea.DesignTokens.attention : Color.foreground
    opacity: 0.75
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: page.pendingKey === 'display-scale' || !!page.results['display-scale']
    text: page.pendingKey === 'display-scale' ? 'Applying…' : page.results['display-scale'] || ''
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !!page.errors['display-scale']
    text: page.errors['display-scale'] || ''
    color: Aranea.DesignTokens.attention
  }
  SettingsButton {
    text: page.detailsExpanded ? 'Hide details' : 'Details'
    variant: 'quiet'
    pointerGate: page.pointerGate
    onClicked: page.detailsExpanded = !page.detailsExpanded
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: page.detailsExpanded
    text: page.scaleDirty && !page.scaleValidation.ok ? page.scaleValidation.message : !page.displayAvailable ? 'Scaling unavailable. Check the compositor and installed Omarchy helper, then Retry.' : page.display.persistenceSupport === 'supported' ? 'Custom scales from 1 to 4. Can save through the standard monitor configuration; the effective fraction may adjust.' : page.display.persistenceSupport === 'unsupported' ? 'Custom scales from 1 to 4. Session only: your monitor configuration does not support saving this control.' : 'Custom scales from 1 to 4. Persistence support could not be read.'
    opacity: 0.65
  }
  SettingsButton {
    text: 'Retry'
    visible: !page.displayAvailable
    enabled: !page.displayOnly && !page.pending
    pointerGate: page.pointerGate
    onClicked: page.retryRequested()
  }
}
