// Local wizard navigation; project mutations remain in the existing page.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

ColumnLayout {
  id: progress
  // Current local setup stage.
  property int step: 0
  // Position of the current repository in this batch, independent of registry order.
  property int projectIndex: 0
  // Distinct repositories registered by this setup, grouping related worktrees.
  property int projectCount: 0
  // Current saved project name provides context while editing preferences.
  property string projectName: ''
  // The host validates successful saves before enabling Next.
  property bool canContinue: false
  // The parent blocks Back while a configuration draft is unsaved.
  property bool canBack: true
  // Registry and scan activity pauses wizard navigation.
  property bool pending: false
  // Inert captures cannot navigate or finish a live setup.
  property bool displayOnly: false
  // Render the progress heading at the top of the stage.
  property bool showSteps: true
  // Render navigation after the stage content.
  property bool showControls: true
  // Shared pointer settling boundary.
  property var pointerGate: null
  // Request guarded backward navigation.
  signal backRequested
  // Request guarded forward navigation.
  signal nextRequested
  // Finish presentation without launching any application.
  signal finishRequested
  // Exit presentation while keeping already saved records.
  signal cancelRequested
  // Ordered human-readable stage labels.
  readonly property var steps: ['Choose folder', 'Add repositories', 'Configure workflow', 'Connect agents']
  // Explain what the user does in each stage.
  readonly property var descriptions: ['Pick your repository folder or its parent development folder. Aranea will scan for Git checkouts.', 'Select the checkouts you want, then Add selected. A checkout is one working copy of a Git repository.', 'Choose your tools and preferred checkout. Save any changes. Test, build, and dev-server actions are optional.', 'Your project is registered. Enable reporting for the agents you use, or finish now and connect them later.']
  spacing: Style.space(8)
  Flow {
    Layout.fillWidth: true
    visible: progress.showSteps
    spacing: Style.space(8)
    Repeater {
      model: progress.steps
      Aranea.UiLabel {
        required property int index
        required property string modelData
        text: (index + 1) + '. ' + modelData
        font.bold: index === progress.step
        color: index === progress.step ? Aranea.DesignTokens.accent : Aranea.DesignTokens.foreground
        opacity: index === progress.step ? 1 : 0.6
      }
    }
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: progress.showSteps
    text: progress.descriptions[progress.step]
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: progress.showSteps && progress.step === 2 && progress.projectCount > 0
    text: 'Project ' + (progress.projectIndex + 1) + ' of ' + progress.projectCount + ' · ' + progress.projectName
    font.bold: true
    color: Aranea.DesignTokens.accent
  }
  Flow {
    Layout.fillWidth: true
    visible: progress.showControls
    spacing: Style.space(8)
    Aranea.ActionButton {
      objectName: 'setupBack'
      text: progress.step === 2 && progress.projectIndex > 0 ? 'Previous project' : 'Back'
      visible: progress.step > 0
      enabled: !progress.displayOnly && !progress.pending && progress.canBack
      pointerGate: progress.pointerGate
      onClicked: progress.backRequested()
    }
    Aranea.ActionButton {
      objectName: 'setupNext'
      text: progress.step === 0 ? 'Review repositories' : progress.step === 2 ? (progress.projectIndex + 1 < progress.projectCount ? 'Next project' : 'Continue to agents') : 'Next'
      visible: progress.step < 3
      enabled: !progress.displayOnly && progress.canContinue && !progress.pending
      pointerGate: progress.pointerGate
      onClicked: progress.nextRequested()
    }
    Aranea.ActionButton {
      objectName: 'setupFinish'
      text: 'Finish setup'
      visible: progress.step === 3
      enabled: !progress.displayOnly && !progress.pending
      pointerGate: progress.pointerGate
      onClicked: progress.finishRequested()
    }
    Aranea.ActionButton {
      text: 'Exit setup'
      enabled: !progress.displayOnly && !progress.pending
      pointerGate: progress.pointerGate
      onClicked: progress.cancelRequested()
    }
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: progress.showControls
    text: progress.step === 1 ? 'Select one or several repositories and Add selected to configure them together.' : progress.step === 2 ? 'Keep the current preferences and continue, or customize this project. Workflow actions are optional; you can add them later.' : progress.step === 3 && progress.projectCount > 1 ? 'All ' + progress.projectCount + ' projects are registered. Reporting is installed once per provider; start agents from the checkout you want to work in.' : 'Existing saved projects are kept when you exit setup.'
    opacity: 0.65
  }
}
