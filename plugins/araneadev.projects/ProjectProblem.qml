// Shared plain-language view of one Projects problem, with its next steps and technical details.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../araneadev.shared" as Aranea

ColumnLayout {
  id: view
  objectName: 'projectProblem'
  // Result of ProjectProblems.problem(), or null to hide the view.
  property var problem: null
  // Capture boundary refuses every external action.
  property bool displayOnly: false
  // The caller's guards allow the action buttons; Copy and Details stay usable.
  property bool actionsEnabled: true
  // Shared pointer settlement gate for moving content.
  property var pointerGate: null
  // Technical details are shown.
  property bool expanded: false
  // Kinds that need the user's attention are tinted.
  readonly property bool attentive: !!view.problem && ['unconfirmed', 'failed', 'notRunning', 'moved', 'missingTool', 'git'].indexOf(view.problem.kind) >= 0
  // Technical lines: the non-empty code, message and recovery.
  readonly property string detailsText: {
    var d = view.problem ? view.problem.details : null
    if (!d)
      return ''
    return [d.code, d.message, d.recovery].filter(function (s) {
      return !!s
    }).join('\n')
  }
  // Copies text to the clipboard; tests replace it.
  property var clipboardRunner: function (text) {
    copyComponent.createObject(view, {
      command: ['wl-copy', text]
    }).running = true
  }
  // The user chose one of the offered next steps.
  signal actionRequested(string id)
  // Move keyboard focus to the first visible action, if any.
  function focusPrimary() {
    for (var i = 0; i < actions.count; i++) {
      var button = actions.itemAt(i)
      if (button && button.visible) {
        button.forceActiveFocus()
        return
      }
    }
  }
  // Technical line handed to the clipboard.
  function copyText() {
    var d = view.problem.details
    return (d.code ? d.code + ': ' : '') + d.message + (d.recovery ? ' (' + d.recovery + ')' : '')
  }
  visible: !!view.problem
  spacing: 6
  // Short-lived clipboard helper that frees itself on exit.
  property Component copyComponent: Component {
    Process {
      id: process
      onRunningChanged: if (!running)
        process.destroy()
    }
  }
  Aranea.UiLabel {
    objectName: 'projectProblemTitle'
    Layout.fillWidth: true
    text: view.problem ? view.problem.title : ''
    font.bold: true
    color: view.attentive ? Aranea.DesignTokens.attention : Aranea.DesignTokens.foreground
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  Aranea.UiLabel {
    objectName: 'projectProblemBody'
    Layout.fillWidth: true
    visible: text !== ''
    text: view.problem ? view.problem.body : ''
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  RowLayout {
    Layout.fillWidth: true
    visible: actions.count > 0
    Repeater {
      id: actions
      model: view.problem ? view.problem.actions : []
      Aranea.ActionButton {
        required property var modelData
        required property int index
        objectName: 'projectProblemAction:' + modelData.id
        text: modelData.label
        variant: index === 0 ? 'primary' : 'secondary'
        enabled: !view.displayOnly && view.actionsEnabled
        pointerGate: view.pointerGate
        onClicked: view.actionRequested(modelData.id)
      }
    }
  }
  RowLayout {
    Layout.fillWidth: true
    Aranea.ActionButton {
      objectName: 'projectProblemDetailsToggle'
      text: view.expanded ? 'Hide details' : 'Details'
      variant: 'quiet'
      pointerGate: view.pointerGate
      onClicked: view.expanded = !view.expanded
    }
    Aranea.ActionButton {
      objectName: 'projectProblemCopy'
      text: 'Copy'
      variant: 'quiet'
      visible: view.expanded
      enabled: !view.displayOnly
      pointerGate: view.pointerGate
      onClicked: view.clipboardRunner(view.copyText())
    }
  }
  Aranea.UiLabel {
    objectName: 'projectProblemDetails'
    Layout.fillWidth: true
    visible: view.expanded
    technical: true
    text: view.detailsText
    opacity: 0.7
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
}
