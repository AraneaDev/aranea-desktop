// Offscreen production workspace panel. No client, compositor or launch owner exists.
import QtQuick
import Quickshell
import qs.Commons
import "plugins/araneadev.workspaces" as Workspaces
import "ProjectPreview.js" as Projects
import "plugins/araneadev.shared" as Aranea

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
      Image {
        id: wallpaper
        anchors.fill: parent
        source: Qt.resolvedUrl('background.png')
        fillMode: Image.PreserveAspectCrop
      }
      Rectangle {
        x: 16
        y: 35
        width: panel.width + 40
        height: panel.implicitHeight + 40
        color: Util.alpha(Aranea.DesignTokens.background, 0.96)
        border.color: Aranea.DesignTokens.surfaceBorder
        radius: Aranea.DesignTokens.cornerRadius
        Aranea.CircuitFrame {
          anchors.fill: parent
        }
        Workspaces.WorkspacePanel {
          id: panel
          x: 20
          y: 20
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
  }
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      if (wallpaper.status === Image.Error) {
        stop()
        console.log('SETTINGSRENDER FAIL background did not load')
        Qt.quit()
        return
      }
      if (wallpaper.status !== Image.Ready)
        return
      surface.grabToImage(function (result) {
        console.log((result.saveToFile(Quickshell.env('ARANEA_SETTINGS_RENDER_OUTPUT')) ? 'SETTINGSRENDER OK ' : 'SETTINGSRENDER FAIL ') + 'workspace panel')
        Qt.quit()
      }, Qt.size(Number(Quickshell.env('ARANEA_SETTINGS_RENDER_WIDTH')), Number(Quickshell.env('ARANEA_SETTINGS_RENDER_HEIGHT'))))
    }
  }
}
