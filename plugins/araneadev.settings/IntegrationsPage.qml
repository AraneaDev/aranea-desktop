// Integration controls delegate activation and ownership to the existing helpers.
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
  // Ask the persistent controller to perform an explicit operation.
  signal request(string operation, var args)
  // Ask the controller to retry a read, never a mutation.
  signal retryRequested
  spacing: Style.space(16)
  SettingsLabel {
    Layout.fillWidth: true
    text: 'Integrations'
    font.pixelSize: Style.font.title
    font.bold: true
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: 'Activate the integrations you use. Existing settings and conflicts are handled by each integration.'
    opacity: 0.65
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !page.backendState.integrations || page.backendState.integrations.length === 0
    text: page.backendState.integrationsAvailability === 'available' ? 'No integrations registered.' : 'Integrations: Unavailable'
  }
  Repeater {
    model: page.backendState.integrations || []
    ColumnLayout {
      id: integrationRow
      required property var modelData
      Layout.fillWidth: true
      spacing: Style.space(8)
      RowLayout {
        Layout.fillWidth: true
        SettingsLabel {
          Layout.fillWidth: true
          text: integrationRow.modelData.label || integrationRow.modelData.id
          font.bold: true
        }
        SettingsButton {
          objectName: 'integrationAction'
          text: integrationRow.modelData.status === 'active' ? 'Deactivate' : 'Activate'
          enabled: !page.pending && page.backendState.integrationsAvailability === 'available' && integrationRow.modelData.availability === 'available'
          busy: page.pendingKey === 'integration:' + integrationRow.modelData.id
          pointerGate: page.pointerGate
          onClicked: page.request('set integration', [integrationRow.modelData.id, integrationRow.modelData.status === 'active' ? 'inactive' : 'active'])
        }
      }
      SettingsLabel {
        Layout.fillWidth: true
        text: page.pendingKey === 'integration:' + integrationRow.modelData.id ? 'Applying…' : page.results['integration:' + integrationRow.modelData.id] || (integrationRow.modelData.availability !== 'available' ? 'Unavailable' : integrationRow.modelData.status === 'active' ? 'Active' : 'Inactive')
        opacity: 0.65
      }
      SettingsLabel {
        Layout.fillWidth: true
        visible: !!page.errors['integration:' + integrationRow.modelData.id]
        text: page.errors['integration:' + integrationRow.modelData.id] || ''
        color: Aranea.DesignTokens.attention
      }
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Util.alpha(Color.foreground, 0.12)
      }
    }
  }
  SettingsButton {
    text: 'Retry'
    enabled: !page.pending
    pointerGate: page.pointerGate
    onClicked: page.retryRequested()
  }
}
