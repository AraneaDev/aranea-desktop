// Production settings controls with every external client inert before activation.
import QtQuick
import Quickshell
import qs.Commons
import "plugins/araneadev.settings" as Settings
import "ProjectPreview.js" as Fixtures

ShellRoot {
  id: harness
  // Assertions fail the renderer without allowing backend execution.
  property int failures: 0
  // Discover production targets through public control text and viewport properties.
  function collect(item, out) {
    if (item.contentY !== undefined || item.text !== undefined || item.objectName === 'settingsScrollBar' || item.objectName === 'projectActions')
      out.push(item)
    var children = item.children || []
    for (var i = 0; i < children.length; i++)
      collect(children[i], out)
    return out
  }
  // Report only independently checked actual production control behavior.
  function check(value, label) {
    console.log('PROJECTCONTROLS ' + (value ? 'PASS ' : 'FAIL ') + label)
    if (!value)
      failures++
  }
  Settings.Settings {
    id: entry
    windowEnabled: false
    runner: function (argv, done) {
      harness.check(false, 'unexpected settings process')
    }
  }
  FloatingWindow {
    implicitWidth: 652
    implicitHeight: 452
    visible: true
    Settings.SettingsSurface {
      id: surface
      anchors.fill: parent
      root: entry
    }
  }
  Component.onCompleted: {
    var actionView = harness.collect(surface, []).filter(function (item) {
      return item.objectName === 'projectActions'
    })[0]
    if (actionView) {
      actionView.displayOnly = true
      actionView.client.runner = function (argv, input, done) {
        harness.check(false, 'unexpected action backend process')
      }
    }
    entry.projectController.captureActive = true
    entry.projectClient.captureActive = true
    entry.discoveryClient.captureActive = true
    entry.projectController.runner = function (argv, input, done) {
      harness.check(false, 'unexpected registry process')
    }
    entry.projectClient.runner = function (argv, done) {
      harness.check(false, 'unexpected owner process')
    }
    entry.discoveryClient.runner = function (argv) {
      harness.check(false, 'unexpected discovery process')
    }
    var fixture = Fixtures.sample('project-launch-partial')
    entry.projectController.state = fixture.projectsState
    entry.projectController.tools = fixture.projectTools
    entry.projectClient.snapshot = fixture.projectSnapshot
    entry.projectClient.available = true
    entry.section = 'projects'
    entry.projectId = 'p-preview'
    entry.opened = true
  }
  Timer {
    interval: 400
    running: true
    onTriggered: {
      entry.projectClient.snapshot = Object.assign({}, entry.projectClient.snapshot)
      Style.fontBaseSize = Math.round(Style.fontBaseSize * 1.5)
      var fonts = Object.assign({}, Style.fontOverrides)
      Object.keys(fonts).forEach(function (k) {
        fonts[k] = Math.round(Number(fonts[k]) * 1.5)
      })
      Style.fontOverrides = fonts
      verify.start()
    }
  }
  Timer {
    id: verify
    interval: 400
    onTriggered: {
      var objects = harness.collect(surface, []), scroll = null, bar = null, retry = null, field = null
      for (var i = 0; i < objects.length; i++) {
        var item = objects[i]
        if (item.contentY !== undefined && item.contentHeight > item.height && item.height > 100)
          scroll = item
        if (item.objectName === 'settingsScrollBar')
          bar = item
        if (item.text === 'Retry terminal' && typeof item.activate === 'function')
          retry = item
        if (item.placeholderText !== undefined && item.text === 'Customer dashboard and developer accessibility improvements')
          field = item
      }
      harness.check(!!scroll && !!bar && !!retry && !!field, 'large-font production viewport and exact recovery targets exist')
      if (scroll && bar && retry && field) {
        surface.scrollTo(0)
        var event = {
          key: Qt.Key_PageDown,
          accepted: false
        }
        surface.handleKey(event)
        harness.check(event.accepted && scroll.contentY > 0, 'actual PageDown handler scrolls Projects')
        surface.scrollTo(0)
        bar.position = 1 - bar.size
        harness.check(scroll.contentY > 0, 'actual pointer scrollbar moves production viewport')
        harness.check(bar.width >= Style.space(8) && bar.interactive, 'pointer scrollbar retains an interactive hit target')
        field.forceActiveFocus(Qt.TabFocusReason)
        surface.revealFocus(field)
        var fieldY = field.mapToItem(scroll.contentItem, 0, 0).y - scroll.contentY
        harness.check(field.activeFocus && fieldY >= -1 && fieldY + field.height <= scroll.height + 1, 'keyboard focus reveals full editable project field')
        retry.forceActiveFocus(Qt.TabFocusReason)
        surface.revealFocus(retry)
        var retryY = retry.mapToItem(scroll.contentItem, 0, 0).y - scroll.contentY
        harness.check(retry.activeFocus && retry.activeFocusOnTab && retryY >= -1 && retryY + retry.height <= scroll.height + 1, 'keyboard focus reveals full failed-role recovery button')
        harness.check(!entry.projectClient.request({
          projectId: 'p-preview',
          checkoutId: 'c-preview',
          retryRole: 'terminal'
        }), 'external owner still refuses mutation')
      }
      surface.grabToImage(function (result) {
        var ok = result.saveToFile(Quickshell.env('ARANEA_SETTINGS_RENDER_OUTPUT')) && harness.failures === 0
        console.log(ok ? 'SETTINGSRENDER OK project control checks' : 'SETTINGSRENDER FAIL project control checks')
        Qt.quit()
      })
    }
  }
}
