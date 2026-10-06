// Notifications IPC controls with read-only quiet-hours observation.
// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

ColumnLayout {
  id: page
  // Independently observed notifications IPC state and per-field availability.
  property var notifications: ({})
  // Whether a settings mutation is in flight.
  property bool pending: false
  // Stable key of the affected control while applying.
  property string pendingKey: ''
  // Latest application outcome for this section.
  property string result: ''
  // Actionable error from the latest read or mutation.
  property string error: ''
  // Per-field IPC read errors.
  property var readErrors: ({})
  // Host pointer movement and layout settling gate.
  property var pointerGate: null
  // Read-only description of the effective quiet-hours state.
  readonly property string quietDescription: notifications.quietAvailability !== 'available' ? 'Unavailable' : notifications.quiet === 'on' ? 'Active now' : notifications.quiet === 'scheduled' ? 'Scheduled' : 'Off'
  // Read-only description of the service-configured quiet-hours window.
  readonly property string windowDescription: notifications.windowAvailability !== 'available' ? 'Unavailable' : notifications.window === 'off' ? 'Not configured' : notifications.window
  // Ask the persistent controller to perform an explicit operation.
  signal request(string operation, var args)
  // Ask the controller to retry a read, never a mutation.
  signal retryRequested
  spacing: Style.space(16)
  SettingsLabel {
    Layout.fillWidth: true
    text: 'Notifications'
    font.pixelSize: Style.font.title
    font.bold: true
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: 'Manage interruptions and check the current quiet-hours window.'
    opacity: 0.65
  }
  RowLayout {
    Layout.fillWidth: true
    SettingsLabel {
      Layout.fillWidth: true
      text: 'Do not disturb'
      font.bold: true
    }
    SettingsToggle {
      objectName: 'dndToggle'
      Accessible.name: 'Do not disturb'
      checked: page.notifications.dnd === 'on'
      enabled: !page.pending && page.notifications.dndAvailability === 'available'
      busy: page.pendingKey === 'dnd'
      pointerGate: page.pointerGate
      onToggled: page.request('set dnd', [checked ? 'off' : 'on'])
    }
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: page.pendingKey === 'dnd' ? 'Applying…' : page.result || (page.notifications.dndAvailability === 'available' ? page.notifications.dnd === 'on' ? 'On' : 'Off' : 'Unavailable')
    opacity: 0.65
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !!page.error || !!page.readErrors.dnd
    text: page.error || page.readErrors.dnd || ''
    color: Aranea.DesignTokens.attention
  }
  Rectangle {
    Layout.fillWidth: true
    implicitHeight: 1
    color: Util.alpha(Color.foreground, 0.12)
  }
  SettingsLabel {
    text: 'Quiet hours'
    font.bold: true
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: 'Effective state: ' + page.quietDescription
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: 'Configured window: ' + page.windowDescription
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: 'Quiet hours are configured by the notification service and shown here read-only.'
    opacity: 0.65
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !!page.readErrors.quiet || !!page.readErrors.window
    text: page.readErrors.quiet || page.readErrors.window || ''
    color: Aranea.DesignTokens.attention
  }
  SettingsButton {
    text: 'Retry'
    enabled: !page.pending
    pointerGate: page.pointerGate
    onClicked: page.retryRequested()
  }
}
