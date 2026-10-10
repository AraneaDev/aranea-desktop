// Actual Settings capture protocol and production actions/editor/run details.
import QtQuick
import Quickshell
import qs.Commons
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: harness
  // Approved inert presentation state for the production capture protocol.
  readonly property string scene: Quickshell.env('ARANEA_ACTION_RENDER_SCENE')
  // Wait for theme/font/layout settlement before checking and capturing.
  property int polls: 0
  // A visual guard or layout failure prevents publishing the artifact.
  property int failures: 0
  // Actual composed view discovered inside SettingsSurface, never stub content.
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
  Settings.Settings {
    id: entry
    windowEnabled: false
    runner: harness.reject
  }
  FloatingWindow {
    implicitWidth: Number(Quickshell.env('ARANEA_ACTION_RENDER_WIDTH'))
    implicitHeight: 680
    visible: true
    Settings.SettingsSurface {
      id: surface
      anchors.fill: parent
      root: entry
    }
  }
  // Supply full inert records and drafts; all rendered controls remain production.
  function sample() {
    var p = 'p-00000000-0000-4000-8000-000000000001'
    var c = 'c-00000000-0000-4000-8000-000000000001'
    var a = 'a-00000000-0000-4000-8000-000000000001'
    var r = 'r-00000000-0000-4000-8000-000000000001'
    var request = 'req-00000000-0000-4000-8000-000000000001'
    var long = scene === 'long-output'
    var path = long ? '/fixture/development/very-long-organization/customer-dashboard/worktrees/accessibility-improvements/build-output' : '/fixture/customer-dashboard';
    var service = ['configured-service', 'editor-service', 'running', 'reachable', 'unreachable', 'unconfirmed'].indexOf(scene) >= 0
    var d = {
      id: a,
      projectId: p,
      name: long ? 'Customer dashboard accessibility validation with a long literal command and separate argument fields' : service ? 'Start preview' : 'Run checks',
      kind: service ? 'service' : 'command',
      argv: ['printf', long ? 'literal $HOME %i ; <b>plain</b> ' + path : 'literal $HOME %i ; <b>plain</b>', ''],
      cwdRelative: '.',
      timeoutSeconds: service ? null : 300,
      previewUrl: service ? 'http://127.0.0.1:8181/' : null,
      revision: 1,
      createdAt: 1700000000,
      updatedAt: 1700000000
    }
    var project = {
      id: p,
      name: 'Customer dashboard',
      commonDir: '/fixture/customer-dashboard/.git',
      lastCheckoutId: c,
      workspaceMode: 'dedicated',
      tools: {
        editorId: 'code',
        terminalId: 'kitty'
      },
      checkouts: [
        {
          id: c,
          path: path,
          branch: 'main',
          primary: true
        }
      ],
      associations: []
    }
    var hasRun = ['running', 'passed', 'failed', 'stopped', 'unconfirmed', 'reachable', 'unreachable', 'long-output'].indexOf(scene) >= 0
    var processState = scene === 'passed' || long ? 'succeeded' : scene === 'failed' ? 'failed' : scene === 'stopped' ? 'stopped' : scene === 'unconfirmed' ? 'unconfirmed' : 'running'
    var run = {
      id: r,
      requestId: request,
      projectId: p,
      checkoutId: c,
      actionId: a,
      definitionRevision: 1,
      definitionHash: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      definitionSnapshot: d,
      cwd: path,
      unitName: 'aranea-project-00000000-0000-4000-8000-000000000001.service',
      bootId: '00000000-0000-4000-8000-000000000001',
      invocationId: scene === 'unconfirmed' ? null : '11111111111111111111111111111111',
      createdAt: 1700000000,
      updatedAt: 1700000000,
      state: 'completed',
      outcome: processState === 'failed' ? 'failed' : processState === 'unconfirmed' ? 'partial' : 'observed',
      processState: processState,
      readiness: scene === 'reachable' ? 'reachable' : scene === 'unreachable' ? 'unreachable' : 'unknown',
      exitCode: processState === 'succeeded' ? 0 : processState === 'failed' ? 7 : null,
      exitSignal: null,
      error: scene === 'unconfirmed' ? {
        code: 'SUBMISSION_UNCONFIRMED',
        message: 'Manager acceptance is unconfirmed.',
        recovery: 'Refresh this exact run; do not resubmit.'
      } : scene === 'failed' ? {
        code: 'COMMAND_FAILED',
        message: 'Command exited with status 7.',
        recovery: 'Read the local journal and review the saved command.'
      } : null,
      stopRequested: scene === 'stopped',
      submissionUnconfirmed: scene === 'unconfirmed'
    }
    var editing = scene.indexOf('editor') >= 0
    var actions = {
      selectedActionId: scene === 'empty' ? '' : a,
      selectedIdentity: [p, c, a, 1].join('|'),
      editing: editing,
      draftProjectId: p,
      snapshot: {
        schemaVersion: 1,
        revision: 1,
        definitions: scene === 'empty' ? [] : [d],
        runs: hasRun ? [run] : [],
        requests: hasRun ? [
          {
            requestId: request,
            hash: 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
            runId: r,
            createdAt: 1700000000
          }
        ] : []
      },
      currentRun: hasRun ? run : null,
      runId: hasRun ? r : '',
      requestId: hasRun ? request : '',
      submissionUncertain: false,
      availability: {
        execution: scene !== 'unavailable-manager',
        userManager: scene !== 'unavailable-manager'
      },
      available: true,
      error: null,
      output: hasRun ? long ? Array(50).join('<b>literal journal output</b> ' + path + '\n') : '<b>literal journal output</b>\nArguments remain plaintext.\n' : '',
      truncated: long
    }
    if (editing)
      actions.editor = {
        draft: {
          id: a,
          name: d.name,
          executable: scene === 'invalid-editor' ? '' : 'printf',
          cwdRelative: '.',
          kind: service ? 'service' : 'command',
          timeoutSeconds: '300',
          previewUrl: service ? d.previewUrl : ''
        },
        argv: d.argv.slice(1),
        expectedRevision: 1,
        fieldError: scene === 'invalid-editor' ? 'Enter an executable name, absolute path or explicit ./path.' : ''
      }
    return {
      state: {},
      projectId: p,
      projectsState: {
        schemaVersion: 1,
        revision: 1,
        roots: [],
        ignored: [],
        projects: [project]
      },
      projectTools: {
        defaults: {
          editorId: 'code',
          terminalId: 'kitty'
        },
        editors: [
          {
            id: 'code',
            label: 'VS Code',
            available: true,
            supported: true
          }
        ],
        terminals: [
          {
            id: 'kitty',
            label: 'Kitty',
            available: true,
            supported: true
          }
        ]
      },
      projectSnapshot: {
        sessionId: 'inert-preview',
        projects: [project],
        bindings: [],
        operations: [],
        availability: {
          ready: true
        }
      },
      projectAvailable: true,
      projectActions: actions
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
    check(!!actionView, 'actual action view composed in SettingsSurface')
    actionView.displayOnly = true
    actionView.client.runner = harness.reject
    var fixture = sample()
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
          return o.contentY !== undefined && o.contentItem && o.height > 100
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
