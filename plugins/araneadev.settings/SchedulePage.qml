// Editable schedule draft kept independently from owner refreshes.
// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
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
  // Local editable daily entries; retained while dirty.
  property var draft: []
  // Whether edits must survive unrelated refreshes and navigation.
  property bool dirty: false
  // Observed schedule configuration and live timer state.
  readonly property var schedule: page.backendState.schedule || ({})
  // Validation and actionable messages for daily entries.
  readonly property var validation: Logic.validateScheduleEntries(draft, backendState.wallpapers || [])
  // Whether the configured section can be safely changed.
  readonly property bool available: schedule.availability === 'available'
  // Catalog reads must be confirmed before committing wallpaper choices.
  readonly property bool editable: available && !displayOnly && !pending
  // Ask the persistent controller to perform an explicit operation.
  signal request(string operation, var args)
  // Ask the controller to retry a read, never a mutation.
  signal retryRequested
  // Refresh clean draft values without discarding local edits.
  function syncDraft() {
    if (!dirty && available)
      draft = Logic.scheduleEntries(schedule)
  }
  // Update a single clock or wallpaper without changing owner state.
  function setDraft(index, value, field) {
    if (!editable || index < 0 || index >= draft.length)
      return
    field = field || 'time'
    if (field !== 'time' && field !== 'wallpaper')
      return
    // Preserve visible draft order while editing; sorting belongs to Save.
    var next = draft.map(function (entry) {
      return {
        time: entry.time,
        wallpaper: entry.wallpaper
      }
    })
    next[index][field] = value
    draft = next
    dirty = true
  }
  // Append an editable row using an available image and unused clock time.
  function addEntry() {
    if (!editable)
      return
    var assets = (backendState.wallpapers || []).filter(function (asset) {
      return asset.available === true
    })
    var time = ''
    for (let minute = 0; minute < 1440; minute++) {
      let clock = ('0' + Math.floor(minute / 60)).slice(-2) + ':' + ('0' + minute % 60).slice(-2)
      if (!draft.some(function (entry) {
        return entry.time === clock
      })) {
        time = clock
        break
      }
    }
    draft = draft.concat([
      {
        time: time,
        wallpaper: assets.length ? assets[0].id : ''
      }
    ])
    dirty = true
  }
  // Keep at least one entry; removing a row never applies changes.
  function removeEntry(index) {
    if (!editable || draft.length <= 1 || index < 0 || index >= draft.length)
      return
    var next = draft.slice()
    next.splice(index, 1)
    draft = next
    dirty = true
  }
  // Submit the normalized daily list while preserving the enabled choice.
  function save() {
    if (editable && backendState.wallpapersAvailability === 'available' && validation.ok)
      request('configure schedule', [JSON.stringify(Logic.normalizeScheduleEntries(draft))])
  }
  // An earlier acknowledgement must not discard newer local edits.
  function acceptSaved(args) {
    var submitted = Logic.submittedScheduleEntries(args)
    if (submitted && validation.ok && JSON.stringify(Logic.scheduleEntries(schedule)) === JSON.stringify(submitted) && JSON.stringify(Logic.normalizeScheduleEntries(draft)) === JSON.stringify(submitted)) {
      dirty = false
      syncDraft()
    }
  }
  // Explicitly discard local edits and adopt current owner entries.
  function discardDraft() {
    if (!editable)
      return
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
    description: 'Choose when each wallpaper appears, every day.'
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
        onToggled: if (page.editable)
          page.request('set schedule', [checked ? 'off' : 'on'])
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
    Repeater {
      model: page.draft.length
      ScheduleEntryRow {
        required property int index
        Layout.fillWidth: true
        entry: page.draft[index] || ({
            time: '',
            wallpaper: ''
          })
        rowNumber: index + 1
        catalog: page.backendState.wallpapers || []
        editable: page.editable
        removable: page.draft.length > 1
        error: page.validation.errors[index] || ''
        pointerGate: page.pointerGate
        onTimeEdited: function (value) {
          page.setDraft(index, value)
        }
        onWallpaperSelected: function (value) {
          page.setDraft(index, value, 'wallpaper')
        }
        onRemoveRequested: page.removeEntry(index)
      }
    }
    SettingsButton {
      objectName: 'scheduleAdd'
      text: 'Add entry'
      enabled: page.editable
      pointerGate: page.pointerGate
      onClicked: page.addEntry()
    }
    SettingsLabel {
      Layout.fillWidth: true
      text: page.dirty && !page.validation.ok ? page.validation.message : 'Use unique 24-hour times. Save sorts entries and keeps the schedule enabled setting.'
      color: page.dirty && !page.validation.ok ? Aranea.DesignTokens.attention : Commons.Color.foreground
      opacity: 0.75
    }
    GridLayout {
      Layout.fillWidth: true
      columns: page.width < Style.space(220) ? 1 : 2
      columnSpacing: Style.space(8)
      rowSpacing: Style.space(8)
      SettingsButton {
        objectName: 'scheduleSave'
        text: 'Save schedule'
        variant: 'primary'
        enabled: page.editable && page.backendState.wallpapersAvailability === 'available' && page.validation.ok
        pointerGate: page.pointerGate
        onClicked: page.save()
      }
      SettingsButton {
        text: 'Discard'
        enabled: page.available && !page.displayOnly && !page.pending
        pointerGate: page.pointerGate
        onClicked: page.discardDraft()
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
    onClicked: if (!page.displayOnly && !page.pending)
      page.retryRequested()
  }
}
