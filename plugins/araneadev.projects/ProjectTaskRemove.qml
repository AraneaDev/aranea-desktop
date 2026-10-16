// Inline confirmation before a task checkout folder is removed; the branch is kept.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../araneadev.shared" as Aranea
import "ProjectTasks.js" as Tasks

ProjectSectionCard {
  id: card
  objectName: 'projectTaskRemove'
  // Registered linked checkout being removed.
  property var checkout: null
  // Removal check facts, or null while the check is running.
  property var facts: null
  // The real removal is running.
  property bool pending: false
  // Any Git command is running anywhere; removing waits for it.
  property bool blocked: false
  // Last check or removal failure as {message, recovery}, or null.
  property var error: null
  // Capture boundary refuses every external action.
  property bool displayOnly: false
  // Shared pointer settlement gate for moving content.
  property var pointerGate: null
  // Plain-language outcome of the facts; empty lines until they arrive.
  readonly property var summary: Tasks.removeSummary(facts)
  // Confirm, with true when the user accepts commits that are on no remote.
  signal confirmRequested(bool confirmUnpushed)
  // Close without removing.
  signal cancelled
  focus: visible
  onVisibleChanged: if (visible)
    card.forceActiveFocus()
  Keys.onEscapePressed: card.cancelled()
  Aranea.UiLabel {
    objectName: 'projectTaskRemoveQuestion'
    Layout.fillWidth: true
    text: card.checkout ? 'Remove the folder ' + card.checkout.path + '? The branch ' + (card.checkout.branch || 'of this checkout') + ' is kept.' : ''
    font.bold: true
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  Aranea.UiLabel {
    objectName: 'projectTaskRemoveChecking'
    Layout.fillWidth: true
    visible: card.facts === null
    text: 'Checking this checkout…'
    opacity: 0.7
  }
  Repeater {
    objectName: 'projectTaskRemoveLines'
    model: card.facts ? card.summary.lines : []
    Aranea.UiLabel {
      required property string modelData
      Layout.fillWidth: true
      text: modelData
      wrapMode: Text.WrapAtWordBoundaryOrAnywhere
    }
  }
  Aranea.UiLabel {
    objectName: 'projectTaskRemoveError'
    Layout.fillWidth: true
    visible: !!card.error
    text: card.error ? card.error.message + ' ' + (card.error.recovery || '') : ''
    color: Aranea.DesignTokens.urgent
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  RowLayout {
    Layout.fillWidth: true
    Aranea.ActionButton {
      objectName: 'projectTaskRemoveConfirm'
      text: card.pending ? 'Removing…' : card.summary.confirmLabel
      enabled: !!card.facts && card.summary.allowed && !card.pending && !card.blocked && !card.displayOnly
      pointerGate: card.pointerGate
      onClicked: card.confirmRequested(!!card.facts && Number(card.facts.unpushed) > 0)
    }
    Aranea.ActionButton {
      objectName: 'projectTaskRemoveCancel'
      text: 'Cancel'
      variant: 'quiet'
      pointerGate: card.pointerGate
      onClicked: card.cancelled()
    }
  }
}
