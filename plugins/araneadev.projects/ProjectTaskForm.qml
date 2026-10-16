// Inline form that names a new task branch; creating never launches anything.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "../araneadev.shared" as Aranea
import "ProjectTasks.js" as Tasks
import "ProjectProblems.js" as Problems

ProjectSectionCard {
  id: form
  objectName: 'projectTaskForm'
  // Registered project whose primary checkout decides the folder.
  property var project: null
  // A create request is running; the form stays open and editable text is kept.
  property bool pending: false
  // Any Git command is running anywhere; creating waits for it.
  property bool blocked: false
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
  readonly property bool canCreate: !pending && !blocked && !displayOnly && problem === ''
  // Identity of the project the typed name belongs to.
  readonly property string projectId: project ? project.id : ''
  onProjectIdChanged: projectTaskBranch.text = ''
  // Ask the surface to create the branch and its checkout.
  signal createRequested(string branch)
  // Close without creating.
  signal cancelled
  // Emit create when the form is valid.
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
  ProjectProblem {
    objectName: 'projectTaskError'
    Layout.fillWidth: true
    displayOnly: form.displayOnly
    pointerGate: form.pointerGate
    problem: form.error ? Problems.problem(form.error, {
      surface: 'tasks',
      actions: []
    }) : null
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
