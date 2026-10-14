// Focused navigation decision; the host alone saves drafts and completes navigation.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

Popup {
  id: guard
  objectName: 'projectDraftGuard'
  // Exact destination stays pending until acknowledged Save or explicit Discard.
  property var pendingTarget: null
  // Accepted mutations prevent duplicate saves or discards.
  property bool pending: false
  // Failed saves retain their draft and actionable backend explanation.
  property string error: ''
  // Reuse the surface's pointer settling boundary.
  property var pointerGate: null
  // The host sends the current editor through its existing save boundary.
  signal saveRequested
  // The host discards local drafts before completing the pending navigation.
  signal discardRequested
  // Dismiss without changing selection or editor values.
  signal keepEditingRequested
  popupType: Popup.Item
  modal: true
  focus: true
  closePolicy: Popup.NoAutoClose
  width: Math.min(parent.width - Style.space(24), Style.space(420))
  x: (parent.width - width) / 2
  y: Math.max(0, (parent.height - height) / 2)
  padding: Style.space(16)
  background: Rectangle {
    color: Color.background
    radius: Style.space(8)
    border.color: Util.alpha(Color.foreground, 0.25)
  }
  contentItem: ColumnLayout {
    spacing: Style.space(12)
    Aranea.UiLabel {
      Layout.fillWidth: true
      text: 'Save your changes?'
      font.bold: true
    }
    Aranea.UiLabel {
      Layout.fillWidth: true
      text: guard.error || 'Save this draft before leaving, discard it, or keep editing.'
    }
    Flow {
      Layout.fillWidth: true
      spacing: Style.space(8)
      Aranea.ActionButton {
        text: 'Save'
        variant: 'primary'
        enabled: !guard.pending
        pointerGate: guard.pointerGate
        onClicked: guard.saveRequested()
      }
      Aranea.ActionButton {
        text: 'Discard'
        enabled: !guard.pending
        pointerGate: guard.pointerGate
        onClicked: guard.discardRequested()
      }
      Aranea.ActionButton {
        text: 'Keep editing'
        enabled: !guard.pending
        pointerGate: guard.pointerGate
        onClicked: guard.keepEditingRequested()
      }
    }
    Keys.onEscapePressed: if (!guard.pending)
      guard.keepEditingRequested()
  }
}
