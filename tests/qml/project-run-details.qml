// Actual retained run view renders immutable evidence and targets exact run IDs.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.settings" as Settings
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: root
  // Observe the exact transport request produced by the actual client.
  property var calls: []
  // Held callbacks drive actual UUID and accepted-restart behavior.
  property var completions: []
  // Existing sole-owner transport remains separate from headless action authority.
  property var focusCalls: []
  QmlTest {
    id: t
  }
  Projects.ProjectClient {
    id: projectClient
    available: true
    snapshot: ({
        availability: {
          compositor: true
        }
      })
    runner: function (argv, done) {
      root.focusCalls.push(JSON.parse(argv[3]))
      done(0, JSON.stringify({
        ok: false,
        error: {
          code: 'OWNER_NOT_READY',
          message: 'Fixture refusal'
        }
      }), '')
    }
  }
  Projects.ProjectActionsClient {
    id: client
    projectId: 'p-one'
    checkoutId: 'c-one'
    runner: function (argv, input, done) {
      root.calls.push([argv[argv.length - 1], JSON.parse(input || '{}')])
      root.completions.push(done)
    }
  }
  Settings.ProjectRunDetails {
    id: details
    width: 320
    client: client
    projectClient: projectClient
    checkout: ({
        id: 'c-one',
        path: '/repo path'
      })
    run: ({
        id: 'r-one',
        projectId: 'p-one',
        checkoutId: 'c-one',
        actionId: 'a-one',
        definitionSnapshot: {
          name: 'Old command',
          kind: 'command',
          argv: ['printf', '<b>literal</b>'],
          cwdRelative: '.'
        },
        cwd: '/repo path',
        processState: 'succeeded',
        exitCode: 0,
        outcome: 'partial',
        submissionUnconfirmed: true,
        readiness: 'reachable',
        createdAt: 1
      })
  }
  Component.onCompleted: t.step(50, function () {
    client.currentRun = details.run
    t.check(details.statusText.indexOf('Cleanup unconfirmed') >= 0, 'terminal main result honestly retains cleanup uncertainty')
    t.check(details.statusText.indexOf('Previous preview reachability') >= 0, 'preview evidence separate from process result')
    t.check(!details.restartAllowed, 'unconfirmed cleanup refuses restart')
    details.perform('restart', 'r-one')
    t.equal(calls.length, 0, 'restart uncertainty never submits')
    details.rememberRun('r-one')
    details.run = Object.assign({}, details.run, {
      id: 'r-two'
    })
    details.releaseRun('stop', 'r-two')
    t.equal(calls.length, 0, 'changed run pointer release cannot transfer Stop')
    details.run = Object.assign({}, details.run, {
      id: 'r-one'
    })
    client.currentRun = details.run
    details.perform('logs', 'r-one')
    t.equal(calls[0], ['logs',
      {
        runId: 'r-one'
      }
    ], 'View logs targets exact retained ID')
    client.pending = false
    client.output = '<b>literal</b>\n' + 'x'.repeat(300000)
    client.runId = 'r-one'
    client.truncated = true
    t.check(details.outputText.length <= 262144, 'output render bounded')
    var output = t.findChild(details, 'actionRunOutput')
    t.check(output.readOnly && output.selectByMouse && output.textFormat === TextEdit.PlainText, 'output readonly selectable plaintext')
    t.check(!!t.findChild(details, 'actionOutputTruncated').visible, 'truncation honestly displayed')
    client.output = '€'.repeat(100000)
    t.check(details.outputText.length * 3 <= 262144, 'multibyte output byte bound respected')
    var statusFixtures = [
      {
        state: 'succeeded',
        expected: 'Command succeeded'
      },
      {
        state: 'failed',
        expected: 'Command failed'
      },
      {
        state: 'stopped',
        expected: 'Stopped'
      },
      {
        state: 'running',
        expected: 'Running'
      },
      {
        state: 'unconfirmed',
        expected: 'Unconfirmed'
      }
    ]
    statusFixtures.forEach(function (fixture) {
      details.run = Object.assign({}, details.run, {
        processState: fixture.state,
        submissionUnconfirmed: false,
        readiness: 'unknown'
      })
      t.check(details.statusText.indexOf(fixture.expected) === 0 && details.statusText.toLowerCase().indexOf('project verified') < 0, fixture.state + ' labels only this command')
    })
    details.run = Object.assign({}, details.run, {
      processState: 'running',
      submissionUnconfirmed: false,
      invocationId: 'pinned',
      definitionSnapshot: {
        name: 'Preview',
        kind: 'service',
        argv: ['preview'],
        previewUrl: 'http://127.0.0.1:3000'
      }
    })
    details.run = Object.assign({}, details.run, {
      definitionRevision: 1
    })
    client.currentRun = details.run
    client.snapshot = {
      revision: 2,
      definitions: [
        {
          id: 'a-one',
          projectId: 'p-one',
          revision: 2
        }
      ],
      runs: [],
      requests: []
    }
    client.pending = false
    t.check(!details.restartAllowed, 'changed current action cannot restart historical command')
    details.perform('restart', 'r-one')
    t.equal(calls.length, 1, 'stale definition restart performs no UUID or backend IO')
    client.snapshot = {
      revision: 3,
      definitions: [
        {
          id: 'a-one',
          projectId: 'p-one',
          revision: 1
        }
      ],
      runs: [],
      requests: []
    }
    t.check(details.restartAllowed, 'unchanged exact definition permits explicit restart')
    details.keyboardIdentity = 'old focused run'
    details.activateRun('stop', 'r-one')
    t.equal(calls.length, 1, 'first keyboard activation on changed run reveals without Stop')
    details.activateRun('stop', 'r-one')
    t.equal(calls[1], ['stop',
      {
        runId: 'r-one'
      }
    ], 'explicit second keyboard activation stops exact run')
    client.pending = false
    details.perform('preview', 'r-one')
    t.equal(calls[2], ['open-preview',
      {
        runId: 'r-one'
      }
    ], 'preview targets eligible exact owned service')
    client.pending = false
    details.perform('refresh', 'r-one')
    t.equal(calls[3], ['refresh',
      {
        runId: 'r-one'
      }
    ], 'Refresh observes exact retained run')
    client.pending = false
    details.perform('focus', 'r-one')
    t.equal(focusCalls[0], {
      projectId: 'p-one',
      checkoutId: 'c-one'
    }, 'Focus uses existing project client for exact checkout')
    client.pending = false
    details.perform('restart', 'r-one')
    completions[4](0, '00000000-0000-4000-8000-000000000099', '')
    t.equal(calls[5][1].expectedDefinitionRevision, 1, 'Restart submits immutable displayed definition revision')
    t.equal(calls[5][1].runId, 'r-one', 'Restart retains exact original run identity')
    var restarted = Object.assign({}, details.run, {
      id: 'r-restarted',
      requestId: 'req-00000000-0000-4000-8000-000000000099'
    })
    completions[5](0, JSON.stringify({
      ok: true,
      error: null,
      run: restarted,
      state: Object.assign({}, client.snapshot, {
        runs: [restarted],
        requests: [
          {
            requestId: restarted.requestId,
            runId: restarted.id
          }
        ]
      })
    }), '')
    t.equal(client.runId, 'r-restarted', 'actual client retains newly accepted restart run ID')
    details.run = client.currentRun
    details.displayOnly = true
    details.perform('refresh', 'r-restarted')
    details.perform('stop', 'r-restarted')
    t.equal(calls.length, 6, 'capture exact-run controls refuse transport')
    details.perform('focus', 'r-restarted')
    t.equal(focusCalls.length, 1, 'capture prevents existing owner Focus request')
    t.done()
  })
}
