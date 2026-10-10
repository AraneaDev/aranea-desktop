// Actual production Tasks/navigation/details in an isolated offscreen window.
import QtQuick
import Quickshell
import qs.Commons
import "plugins/araneadev.agents" as Agents

ShellRoot {
  id: host
  // Renderer chooses only fixed fixtures, never executable provider text.
  readonly property string fixture: Quickshell.env('ARANEA_AGENTS_RENDER_FIXTURE')
  // A deterministic report time keeps receipt age independently visible.
  readonly property double now: 1800000000000
  // Wait for font/layout completion before grabbing production content.
  property int ticks: 0
  // Snapshot construction is pure; no client, runtime, collector or provider is loaded.
  function task(state, index) {
    return {
      taskId: 'preview-' + index,
      provider: index % 2 ? 'codex' : 'claude',
      source: 'native',
      nativeSessionEligible: true,
      providerSessionId: '12345678-1234-1234-1234-123456789abc',
      producerEpoch: 'preview',
      reportedState: state === 'connection-lost' ? 'working' : state,
      displayState: state,
      freshness: state === 'connection-lost' ? 'connection-lost' : 'connected',
      lastReceivedAt: now / 1000 - 37,
      description: fixture === 'long' ? 'Inspect keyboard reachability, narrow layouts, and independently reported verification across a very long checkout path and description.' : 'Improve keyboard navigation in project settings',
      question: state === 'needs-input' ? 'Which checkout should receive the accessibility changes?' : '',
      blockers: state === 'needs-input' ? [
        {
          blockerId: 'question',
          question: 'Choose the target checkout in your agent terminal.'
        }
      ] : [],
      result: state === 'ready-for-review' || state === 'finished' ? 'Navigation changes are ready for inspection. No verification result was reported.' : '',
      diagnostics: state === 'failed' ? [
        {
          summary: 'The requested verification command failed; inspect the reported output in your agent terminal.'
        }
      ] : [],
      verification: {
        status: 'unknown',
        summary: '',
        commands: []
      },
      resumeCommand: 'claude --resume 12345678-1234-1234-1234-123456789abc',
      association: {
        status: 'registered',
        projectId: 'preview-project',
        checkoutId: 'preview-checkout' + (fixture === 'long' ? index : ''),
        cwd: host.checkoutPath(index)
      }
    }
  }
  // Duplicate checkout basenames and branch labels expose exact full paths.
  function checkoutPath(index) {
    return fixture === 'long' ? '/home/dev/work/customer-dashboard/accessibility/' + (index ? 'review-copies/deeply-nested/customer-dashboard' : 'development-copies/deeply-nested/customer-dashboard') : '/home/dev/work/customer-dashboard/accessibility/improve-keyboard-navigation'
  }
  FloatingWindow {
    implicitWidth: Number(Quickshell.env('ARANEA_AGENTS_RENDER_WIDTH'))
    implicitHeight: Number(Quickshell.env('ARANEA_AGENTS_RENDER_HEIGHT'))
    visible: true
    color: 'transparent'
    Rectangle {
      id: surface
      anchors.fill: parent
      color: Color.background
      border.color: Color.accent
      radius: 14
      Column {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 12
        Text {
          text: 'Agents'
          color: Color.foreground
          font.pixelSize: Style.font.heading
          font.bold: true
        }
        Agents.AgentTaskNavigation {
          id: navigation
          width: parent.width
          taskRows: tasks.taskRows
          remembered: 'tasks'
          usageCount: 0
        }
        Agents.AgentTasks {
          id: tasks
          width: parent.width
          maxHeight: surface.height - 120
          captureActive: true
          nowMs: host.now
          projectSnapshot: ({
              projects: [
                {
                  id: 'preview-project',
                  name: 'Customer dashboard',
                  checkouts: (host.fixture === 'long' ? [0, 1] : [0]).map(function (index) {
                    return {
                      id: 'preview-checkout' + (host.fixture === 'long' ? index : ''),
                      branch: 'accessibility/navigation',
                      path: host.checkoutPath(index)
                    }
                  })
                }
              ]
            })
          onAction: function (kind, taskId) {
            console.log('AGENTSRENDER FAIL unexpected action ' + kind)
            Qt.quit()
          }
        }
      }
    }
  }
  Component.onCompleted: {
    Style.spacingScale = 1
    Style.spacingScaleWithFont = false
    var states = {
      working: 'working',
      'needs-input': 'needs-input',
      review: 'ready-for-review',
      failed: 'failed',
      lost: 'connection-lost',
      finished: 'finished',
      long: 'needs-input',
      partial: 'connection-lost',
      pending: 'connection-lost'
    }
    var list = fixture === 'empty' ? [] : fixture === 'mixed' ? ['working', 'needs-input', 'ready-for-review', 'failed', 'connection-lost', 'finished'] : fixture === 'long' ? ['needs-input', 'needs-input'] : [states[fixture]]
    tasks.snapshot = {
      tasks: list.map(function (state, index) {
        return host.task(state, index)
      }),
      operations: []
    }
    if (fixture === 'partial' || fixture === 'pending')
      tasks.operation = {
        id: 'preview-operation',
        ownerId: 'preview-owner',
        taskId: 'preview-0',
        action: 'reopen',
        state: fixture === 'pending' ? 'observing' : 'completed',
        outcome: 'partial',
        submissionPending: fixture === 'pending',
        steps: [
          {
            role: 'hosting-terminal',
            status: 'observed'
          },
          {
            role: 'session',
            status: 'unconfirmed'
          }
        ]
      }
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      host.ticks++
      if (host.ticks === 3) {
        var scale = Number(Quickshell.env('ARANEA_AGENTS_RENDER_FONT_SCALE') || 1)
        Style.fontBaseSize = Math.round(Style.fontBaseSize * scale)
        var fonts = Object.assign({}, Style.fontOverrides)
        Object.keys(fonts).forEach(function (key) {
          fonts[key] = Math.round(Number(fonts[key]) * scale)
        })
        Style.fontOverrides = fonts
      }
      if (host.ticks === 6 && (Quickshell.env('ARANEA_AGENTS_RENDER_DETAILS') === '1' || host.fixture === 'partial' || host.fixture === 'pending'))
        tasks.openDetails('preview-0')
      if (host.ticks >= 10) {
        stop()
        if (!surface.grabToImage(function (result) {
          console.log(result.saveToFile(Quickshell.env('ARANEA_AGENTS_RENDER_OUTPUT')) ? 'AGENTSRENDER OK' : 'AGENTSRENDER FAIL save')
          Qt.quit()
        }, Qt.size(surface.width, surface.height))) {
          console.log('AGENTSRENDER FAIL grab')
          Qt.quit()
        }
      }
    }
  }
}
