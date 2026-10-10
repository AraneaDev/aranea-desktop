// Useful first destination when no saved project selection is available.
// qmllint disable missing-property
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

ProjectSectionCard {
  id: welcome
  objectName: 'projectsWelcome'
  // Select-first guidance differs from the initial empty registry.
  property bool hasProjects: false
  // Setup remains unavailable while an operation or draft blocks navigation.
  property bool pending: false
  // Capture fixtures never start setup or backend requests.
  property bool displayOnly: false
  // Shared pointer settling gate supplied by the main surface.
  property var pointerGate: null
  // Enter the existing setup wizard after the parent checks its guards.
  signal setupRequested
  // Show offline guidance without contacting a backend.
  signal helpRequested
  Aranea.UiLabel {
    Layout.fillWidth: true
    text: welcome.hasProjects ? 'Choose a project to get started' : 'Your projects, in one place'
    font.pixelSize: Style.font.heading
    font.bold: true
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    text: welcome.hasProjects ? 'Select a project from the list to open its workspace, run actions, or see what your agents are doing.' : 'Add a Git repository, choose your editor and terminal, and keep your workflow close at hand.'
    font.pixelSize: Style.font.body
    opacity: 0.8
  }
  Rectangle {
    Layout.fillWidth: true
    implicitHeight: 1
    color: Util.alpha(Color.foreground, 0.1)
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    text: 'Workspace · Open your editor and terminal together.\nActions · Save commands you run regularly.\nAgents · Follow tasks associated with each project.'
    lineHeight: 1.5
  }
  Flow {
    Layout.fillWidth: true
    spacing: Style.space(8)
    Aranea.ActionButton {
      objectName: 'welcomeAddProject'
      text: 'Add project'
      variant: 'primary'
      enabled: !welcome.displayOnly && !welcome.pending
      pointerGate: welcome.pointerGate
      onClicked: welcome.setupRequested()
    }
    Aranea.ActionButton {
      text: 'How Projects works'
      pointerGate: welcome.pointerGate
      onClicked: welcome.helpRequested()
    }
  }
}
