// Editable schedule draft kept independently from owner refreshes.
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
  // Latest application outcome for this section.
  property string result: ''
  // Actionable error from the latest read or mutation.
  property string error: ''
  // Host pointer movement and layout settling gate.
  property var pointerGate: null
  // Local editable phase times; retained while dirty.
  property var draft: ['', '', '', '']
  // Whether edits must survive unrelated refreshes and navigation.
  property bool dirty: false
  // Observed schedule configuration and live timer state.
  readonly property var schedule: page.backendState.schedule || ({})
  // Validation result for all four local phase times.
  readonly property var validation: Logic.validateSchedule(draft)
  // Whether the configured section can be safely changed.
  readonly property bool available: schedule.availability === 'available'
  // Ask the persistent controller to perform an explicit operation.
  signal request(string operation, var args)
  // Ask the controller to retry a read, never a mutation.
  signal retryRequested
  // Refresh clean draft values without discarding local edits.
  function syncDraft() {
    if (!dirty && available)
      draft = [schedule.dawn || '', schedule.day || '', schedule.dusk || '', schedule.night || '']
  }
  // Update one editable phase time and mark the draft dirty.
  function setDraft(index, value) {
    var next = draft.slice()
    next[index] = value
    draft = next
    dirty = true
  }
  // Emit explicit Save only when all phase times are valid.
  function save() {
    if (!displayOnly && !pending && available && validation.ok)
      request('configure schedule', draft.slice())
  }
  // Mark an explicitly saved draft clean only when owner configuration matches.
  function acceptSaved(args) {
    var current = [schedule.dawn, schedule.day, schedule.dusk, schedule.night]
    if (JSON.stringify(current) === JSON.stringify(args) && JSON.stringify(draft) === JSON.stringify(args))
      dirty = false
  }
  // Discard local edits explicitly and adopt current owner configuration.
  function useCurrentTimes() {
    dirty = false
    syncDraft()
  }
  onScheduleChanged: syncDraft()
  onAvailableChanged: syncDraft()
  Component.onCompleted: syncDraft()
  spacing: Style.space(12)
  SettingsPageHeader {
    Layout.fillWidth: true
    title: 'Wallpaper schedule'
    description: 'Move through dawn, day, dusk and night.'
  }
  SettingsSection {
    Layout.fillWidth: true
    title: 'Schedule'
    RowLayout {
      Layout.fillWidth: true
      SettingsLabel {
        text: 'Enable schedule'
        font.bold: true
      }
      SettingsToggle {
        objectName: 'scheduleToggle'
        Accessible.name: 'Enable wallpaper schedule'
        checked: page.schedule.enabled === true
        enabled: !page.displayOnly && !page.pending && page.available
        busy: page.pendingKey === 'schedule'
        pointerGate: page.pointerGate
        onToggled: page.request('set schedule', [checked ? 'off' : 'on'])
      }
      Item {
        Layout.fillWidth: true
      }
    }
    SettingsLabel {
      Layout.fillWidth: true
      text: !page.available ? 'Unavailable' : page.pendingKey === 'schedule' ? 'Applying…' : page.result || (page.schedule.applied === null ? 'Timer state unavailable' : page.schedule.applied ? 'Timer active' : 'Timer inactive')
      opacity: 0.65
    }
    GridLayout {
      Layout.fillWidth: true
      columns: width < Style.space(420) ? 1 : 2
      columnSpacing: Style.space(12)
      rowSpacing: Style.space(8)
      Repeater {
        model: ['Dawn', 'Day', 'Dusk', 'Night']
        ColumnLayout {
          id: phase
          required property int index
          required property string modelData
          Layout.fillWidth: true
          SettingsLabel {
            text: phase.modelData
          }
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(28)
            color: Util.alpha(Color.foreground, 0.04)
            radius: Style.space(3)
            border.width: 1
            border.color: field.activeFocus ? Aranea.DesignTokens.accent : Util.alpha(Color.foreground, 0.15)
            TextInput {
              id: field
              objectName: 'phaseTime'
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              verticalAlignment: TextInput.AlignVCenter
              text: page.draft[phase.index] || ''
              color: Color.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
              enabled: page.available && !page.displayOnly && !page.pending
              activeFocusOnTab: true
              selectByMouse: true
              maximumLength: 5
              Accessible.name: phase.modelData + ' time'
              onTextEdited: page.setDraft(phase.index, text)
            }
          }
        }
      }
    }
    SettingsLabel {
      Layout.fillWidth: true
      text: page.dirty && !page.validation.ok ? page.validation.message : 'Use 24-hour times. Saving times keeps the schedule enabled setting.'
      color: page.dirty && !page.validation.ok ? Aranea.DesignTokens.attention : Color.foreground
      opacity: 0.75
    }
    GridLayout {
      Layout.fillWidth: true
      columns: page.width < Style.space(220) ? 1 : 2
      columnSpacing: Style.space(8)
      rowSpacing: Style.space(8)
      SettingsButton {
        objectName: 'scheduleSave'
        text: 'Save times'
        variant: 'primary'
        enabled: page.available && !page.displayOnly && !page.pending && page.validation.ok
        pointerGate: page.pointerGate
        onClicked: page.save()
      }
      SettingsButton {
        text: 'Discard'
        enabled: page.available && !page.displayOnly && !page.pending
        pointerGate: page.pointerGate
        onClicked: page.useCurrentTimes()
      }
    }
    SettingsLabel {
      Layout.fillWidth: true
      visible: !!page.error
      text: page.error
      color: Aranea.DesignTokens.attention
    }
  }
  SettingsButton {
    text: 'Retry'
    visible: !page.available
    enabled: !page.displayOnly && !page.pending
    pointerGate: page.pointerGate
    onClicked: page.retryRequested()
  }
}
