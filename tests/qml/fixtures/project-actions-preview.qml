// Actual Projects capture protocol and production actions/editor/run details.
import QtQuick
import Quickshell
import qs.Commons
import "plugins/araneadev.projects" as Projects
import "ProjectActionsPreview.js" as ActionsPreview

ShellRoot {
  id: harness
  // Approved inert presentation state for the production capture protocol.
  readonly property string scene: Quickshell.env('ARANEA_ACTION_RENDER_SCENE')
  // Wait for theme/font/layout settlement before checking and capturing.
  property int polls: 0
  // A visual guard or layout failure prevents publishing the artifact.
  property int failures: 0
  // Actual composed view discovered inside ProjectsSurface, never stub content.
  property var actionView: null
  // Report independent capture/geometry assertions to the renderer.
  function check(value, label) {
    console.log('ACTIONRENDER ' + (value ? 'PASS ' : 'FAIL ') + label)
    if (!value)
      failures++
  }
  // Any transport request is forbidden even before external command traps.
  function reject() {
    check(false, 'unexpected process transport')
  }
  // Traverse actual declared/control children and scrolling content once.
  function collect(item, out) {
    var children = item.data || item.children || []
    for (var i = 0; i < children.length; i++) {
      if (out.indexOf(children[i]) >= 0)
        continue
      out.push(children[i])
      collect(children[i], out)
    }
    if (item.contentItem && out.indexOf(item.contentItem) < 0) {
      out.push(item.contentItem)
      collect(item.contentItem, out)
    }
    return out
  }
  Projects.ProjectsPresentation {
    id: entry
    windowEnabled: false
  }
  FloatingWindow {
    implicitWidth: Number(Quickshell.env('ARANEA_ACTION_RENDER_WIDTH'))
    implicitHeight: Number(Quickshell.env('ARANEA_ACTION_RENDER_HEIGHT') || 680)
    visible: true
    Projects.ProjectsSurface {
      id: surface
      anchors.fill: parent
      root: entry
    }
  }
  Component.onCompleted: {
    Style.spacingScale = 1
    Style.spacingScaleWithFont = false
    entry.view = surface
    entry.projectController.runner = harness.reject
    entry.projectClient.runner = harness.reject
    entry.discoveryClient.runner = harness.reject
    actionView = collect(surface, []).filter(function (o) {
      return o.objectName === 'projectActions'
    })[0]
    check(!!actionView, 'actual action view composed in ProjectsSurface')
    actionView.displayOnly = true
    actionView.client.runner = harness.reject
    // The shared scene fixture also feeds the live desktop capture.
    var fixture = ActionsPreview.sample(harness.scene)
    check(entry.captureBegin(JSON.stringify({
      snapshot: entry.captureSnapshot(),
      section: 'projects',
      projectId: fixture.projectId,
      fixture: fixture
    })) === 'ok', 'production capture admitted')
  }
  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      harness.polls++
      if (harness.polls === 3) {
        var scale = Number(Quickshell.env('ARANEA_ACTION_RENDER_FONT_SCALE'))
        Style.fontBaseSize = Math.round(Style.fontBaseSize * scale)
        var fonts = Object.assign({}, Style.fontOverrides)
        Object.keys(fonts).forEach(function (key) {
          fonts[key] = Math.round(Number(fonts[key]) * scale)
        })
        Style.fontOverrides = fonts
      }
      if (harness.polls === 8) {
        var state = JSON.parse(entry.captureState())
        harness.check(state.ready && state.readOnly, 'capture protocol ready and read only')
        var client = harness.actionView.client
        harness.check(client.captureActive && harness.actionView.displayOnly, 'capture guards actual client before UUID/read/poll')
        var before = JSON.stringify(harness.actionView.captureSnapshot())
        harness.actionView.refresh()
        client.refresh()
        client.checkAvailability()
        client.readRun()
        client.start('a-00000000-0000-4000-8000-000000000001', 1)
        client.logs(client.runId)
        client.stop(client.runId)
        client.restart(client.runId)
        client.openPreview(client.runId)
        harness.actionView.editor.save()
        harness.check(before === JSON.stringify(harness.actionView.captureSnapshot()), 'all capture I/O controls leave presentation unchanged')
        var objects = harness.collect(surface, [])
        var scroll = objects.filter(function (o) {
          return o.objectName === 'projectsContentViewport' && o.contentY !== undefined && o.contentItem && o.height > 100
        })[0]
        harness.check(!!scroll, 'production settings viewport exists even when compact content fits')
        if (!scroll)
          return
        // Capture guards disable mutation buttons. Temporarily enable focus only;
        // no handler is activated, and runner still rejects every transport.
        var controls = objects.filter(function (o) {
          return o.visible && o.objectName && (/^actionRun:|^actionStart:|^actionSave$|^actionCancel$|^actionExecutable$/.test(o.objectName))
        })
        harness.check(controls.length > 0 || harness.scene === 'empty', 'actual scene controls exist')
        controls.forEach(function (control) {
          var enabled = control.enabled
          control.enabled = true
          control.forceActiveFocus(Qt.TabFocusReason)
          surface.revealFocus(control)
          var y = control.mapToItem(scroll.contentItem, 0, 0).y - scroll.contentY
          harness.check(control.activeFocus && y >= -1 && y + control.height <= scroll.height + 1, 'focus reveals ' + control.objectName)
          control.enabled = enabled
        })
        var output = objects.filter(function (o) {
          return o.objectName === 'actionRunOutput' && o.visible
        })[0]
        if (output)
          harness.check(output.readOnly && output.selectByMouse && output.textFormat === TextEdit.PlainText && output.text.length <= 262144, 'bounded readonly selectable plaintext output')
        var targetName = harness.scene.indexOf('editor') >= 0 ? 'actionExecutable' : harness.actionView.client.currentRun ? 'actionRunStatus' : 'projectActions'
        var target = objects.filter(function (o) {
          return o.objectName === targetName
        })[0]
        surface.scrollTo(Quickshell.env('ARANEA_ACTION_RENDER_SCROLL') === 'bottom' ? Math.max(0, scroll.contentHeight - scroll.height) : Math.min(Math.max(0, target.mapToItem(scroll.contentItem, 0, 0).y - 12), Math.max(0, scroll.contentHeight - scroll.height)))
      }
      if (harness.polls === 12) {
        stop()
        surface.grabToImage(function (result) {
          var ok = result.saveToFile(Quickshell.env('ARANEA_ACTION_RENDER_OUTPUT')) && harness.failures === 0
          console.log(ok ? 'ACTIONRENDER OK' : 'ACTIONRENDER FAILED')
          Qt.quit()
        }, Qt.size(surface.width, surface.height))
      }
    }
  }
}
