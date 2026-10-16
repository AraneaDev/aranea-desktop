// Inline form that names a new task branch; creating never launches anything.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "../araneadev.shared" as Aranea
import "ProjectTasks.js" as Tasks

ProjectSectionCard {
  id: form
  objectName: 'projectTaskForm'
  // Registered project whose primary checkout decides the folder.
  property var project: null
  // A create request is running; the form stays open and editable text is kept.
  property bool pending: false
  // Last create failure as {message, recovery}, or null.
  property var error: null
  // Capture boundary refuses every external action.
  property bool displayOnly: false
  // Shared pointer settlement gate for moving content.
  property var pointerGate: null
  // Typed branch name, exactly as entered.
  readonly property string branch: projectTaskBranch.text
  // Obvious problem with the typed name, or ''.
  readonly property string problem: Tasks.branchProblem(branch)
  // Create is allowed for a plausible name while nothing is running.
  readonly property bool canCreate: !pending && !displayOnly && problem === ''
  // Ask the surface to create the branch and its checkout.
  signal createRequested(string branch)
  // Close without creating.
  signal cancelled
  function submit() {
    if (canCreate)
      createRequested(branch)
  }
  onVisibleChanged: if (visible)
    projectTaskBranch.forceActiveFocus()
  Keys.onEscapePressed: form.cancelled()
  Aranea.UiLabel {
    text: 'New task checkout'
    font.bold: true
  }
  Ui.TextField {
    id: projectTaskBranch
    objectName: 'projectTaskBranch'
    Layout.fillWidth: true
    enabled: !form.displayOnly && !form.pending
    placeholderText: 'Branch name, for example feat/login'
    Accessible.name: 'Task branch name'
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: Style.font.body
    onAccepted: form.submit()
    Keys.onEscapePressed: form.cancelled()
  }
  Aranea.UiLabel {
    objectName: 'projectTaskPreview'
    Layout.fillWidth: true
    text: form.problem === '' ? 'From the default branch · ' + Tasks.taskFolder(form.project, form.branch) : form.problem
    opacity: 0.7
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  Aranea.UiLabel {
    objectName: 'projectTaskError'
    Layout.fillWidth: true
    visible: !!form.error
    text: form.error ? form.error.message + ' ' + (form.error.recovery || '') : ''
    color: Aranea.DesignTokens.urgent
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  RowLayout {
    Layout.fillWidth: true
    Aranea.ActionButton {
      objectName: 'projectTaskCreate'
      text: form.pending ? 'Creating task checkout…' : 'Create'
      enabled: form.canCreate
      pointerGate: form.pointerGate
      onClicked: form.submit()
    }
    Aranea.ActionButton {
      objectName: 'projectTaskCancel'
      text: 'Cancel'
      variant: 'quiet'
      pointerGate: form.pointerGate
      onClicked: form.cancelled()
    }
  }
}
