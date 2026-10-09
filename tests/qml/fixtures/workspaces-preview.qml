// Offscreen production workspace panel. No client, compositor or launch owner exists.
import QtQuick
import Quickshell
import qs.Commons
import "plugins/araneadev.workspaces" as Workspaces
import "ProjectPreview.js" as Projects

ShellRoot {
  FloatingWindow {
    implicitWidth: Number(Quickshell.env('ARANEA_SETTINGS_RENDER_WIDTH'))
    implicitHeight: Number(Quickshell.env('ARANEA_SETTINGS_RENDER_HEIGHT'))
    color: '#17151f'
    visible: true
    Rectangle {
      id: surface
      anchors.fill: parent
      color: '#101315'
      Workspaces.WorkspacePanel {
        id: panel
        anchors.centerIn: parent
        width: 420
        height: implicitHeight
        maxContentHeight: 500
        cursorIndex: 0
        projectSnapshot: Projects.sample('projects-grouped').projectSnapshot
        workspaceStates: [
          {
            id: 3,
            name: '3',
            focused: true,
            urgent: false,
            windows: 2,
            titles: ['Customer dashboard']
          },
          {
            id: 4,
            name: '4',
            focused: false,
            urgent: false,
            windows: 0,
            titles: []
          }
        ]
        onFocusWorkspace: console.log('SETTINGSRENDER FAIL unexpected dispatch')
      }
    }
  }
  Timer {
    interval: 1000
    running: true
    onTriggered: surface.grabToImage(function (result) {
      console.log((result.saveToFile(Quickshell.env('ARANEA_SETTINGS_RENDER_OUTPUT')) ? 'SETTINGSRENDER OK ' : 'SETTINGSRENDER FAIL ') + 'workspace panel')
      Qt.quit()
    }, Qt.size(Number(Quickshell.env('ARANEA_SETTINGS_RENDER_WIDTH')), Number(Quickshell.env('ARANEA_SETTINGS_RENDER_HEIGHT'))))
  }
}
