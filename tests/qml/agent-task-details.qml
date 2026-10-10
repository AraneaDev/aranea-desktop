// Inert details/actions tests for exact task identities and retained outcomes.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.agents" as Agents
import "plugins/araneadev.agents/AgentTasksLogic.js" as Logic

ShellRoot {
  id: host
  // View actions are recorded without invoking clients.
  property var actions: []
  TestCase {
    id: pointer
    name: "detailsPointer"
    when: false
  }
  QmlTest {
    id: t
  }
  FloatingWindow {
    visible: true
    width: 300
    height: 500
    Agents.AgentTaskDetails {
      id: view
      width: 250
      maxHeight: 240
      row: Logic.rows({
        tasks: [
          {
            taskId: 'stable',
            provider: 'claude',
            source: 'native',
            nativeSessionEligible: true,
            description: '<b>Fix</b>',
            result: 'result',
            question: 'question',
            diagnostics: [
              {
                summary: 'diagnostic'
              }
            ],
            reportedState: 'connection-lost',
            displayState: 'connection-lost',
            freshness: 'connection-lost',
            resumeCommand: "claude --resume 'uuid'",
            verification: {
              status: 'unknown'
            },
            association: {
              status: 'registered',
              projectId: 'p',
              checkoutId: 'c',
              cwd: '/repo'
            }
          }
        ]
      }, {
        projects: [
          {
            id: 'p',
            name: 'Project',
            checkouts: [
              {
                id: 'c',
                path: '/repo',
                branch: 'main'
              }
            ]
          }
        ]
      })[0]
      onAction: function (kind, taskId) {
        host.actions.push([kind, taskId])
      }
    }
  }
  Component.onCompleted: t.step(80, function () {
    t.equal(t.findChild(view, 'reportedResult').text, 'result', 'reported result stays separate')
    t.equal(t.findChild(view, 'reportedQuestion').text, 'question', 'reported question stays separate')
    t.equal(t.findChild(view, 'reportedDiagnostics').text, 'diagnostic', 'diagnostic stays separate')
    t.equal(t.findChild(view, 'reportedVerification').text, 'Verification not reported', 'finished status never implies verification')
    t.equal(t.findChild(view, 'detailsSummary').textFormat, Text.PlainText, 'summary is plaintext')
    t.check(t.findChild(view, 'hostingTerminalNote').text.indexOf('pane') >= 0, 'hosting terminal limitation is explained')
    t.check(view.scroll.contentHeight > view.scroll.height && view.height <= 240, 'large details scroll within narrow cap')
    view.navigate(0)
    t.equal(actions.length, 0, 'first details Enter only reveals action cursor')
    view.navigate(0)
    t.equal(actions.pop(), ['reopen', 'stable'], 'confirmed action uses task identity')
    view.operation = {
      id: 'op',
      taskId: 'stable',
      action: 'reopen',
      state: 'completed',
      outcome: 'partial',
      steps: [
        {
          role: 'terminal',
          status: 'observed'
        },
        {
          role: 'session',
          status: 'unconfirmed'
        }
      ]
    }
    t.check(view.actionKinds.indexOf('reobserve') >= 0, 'partial operation offers explicit observation')
    t.equal(t.findChild(view, 'operationSteps').text, 'Hosting terminal: observed\nNative session: unconfirmed', 'partial outcome preserves independent steps')
    view.operation = {
      id: 'op',
      taskId: 'stable',
      action: 'reopen',
      state: 'completed',
      outcome: 'partial',
      submissionUnconfirmed: true
    }
    t.check(view.actionKinds.indexOf('reobserve') < 0 && view.actionKinds.indexOf('reopen') < 0, 'uncertain acceptance prevents a repeat')
    t.check(t.findChild(view, 'operationStatus').text.indexOf('unconfirmed') >= 0, 'acceptance uncertainty stays visible')
    view.error = {
      code: 'OPERATION_LOST',
      message: 'Owner changed',
      recovery: 'Check the existing terminal before any new launch.'
    }
    t.check(view.actionKinds.indexOf('reconnect') >= 0, 'retained outcome offers read-only reconnect')
    view.pending = true
    t.check(view.actionKinds.indexOf('reopen') < 0, 'pending request blocks launch')
    view.pending = false
    view.operation = null
    view.error = null
    view.cursorKind = 'reopen'
    view.keyboardCursor = true
    view.row = Object.assign({}, view.row, {
      key: 'new-task'
    })
    view.navigate(0)
    t.equal(actions.length, 0, 'new task cannot inherit action Enter')
    view.layoutChangedAt = Date.now()
    t.equal(view.activateKind('dismiss', true), false, 'pointer settling blocks action')
    view.navigate(0)
    view.navigate(0)
    actions = []
    view.disarmCursor()
    view.navigate(0)
    t.equal(actions.length, 0, 'disarming details cursor requires another reveal')
    view.operation = null
    view.error = null
    view.row = Logic.rows({
      tasks: [
        {
          taskId: 'finished-local',
          provider: 'claude',
          reportedState: 'finished',
          displayState: 'finished',
          freshness: 'connected',
          source: 'report',
          result: 'Final plaintext result',
          association: {
            status: 'unassigned',
            cwd: '/manual'
          }
        }
      ]
    })[0]
    t.equal(view.actionKinds[0], 'inspect-result', 'finished task leads with local result inspection')
    actions = []
    view.navigate(0)
    view.navigate(0)
    t.equal(actions.pop(), ['inspect-result', 'finished-local'], 'result control has a fixed local action and exact task ID')
    t.check(view.scroll.contentY < view.scroll.contentHeight - view.scroll.height, 'confirmed result inspection scrolls to result rather than actions')
    view.row = Logic.rows({
      tasks: [
        {
          taskId: 'failed-local',
          provider: 'claude',
          reportedState: 'failed',
          displayState: 'failed',
          freshness: 'connected',
          source: 'native',
          nativeSessionEligible: true,
          resumeCommand: 'fixed display-only command',
          diagnostics: [
            {
              summary: 'Failure details'
            }
          ],
          association: {
            status: 'registered',
            projectId: 'p',
            checkoutId: 'c',
            cwd: '/repo'
          }
        }
      ]
    }, {
      projects: [
        {
          id: 'p',
          name: 'Project',
          checkouts: [
            {
              id: 'c',
              path: '/repo'
            }
          ]
        }
      ]
    })[0]
    t.equal(view.actionKinds[0], 'inspect-failure', 'failed task leads with local failure inspection')
    t.check(view.actionKinds.indexOf('reopen') >= 0 && view.actionKinds.indexOf('focus') < 0, 'failure offers explicit resume without working-session focus')
    t.check(view.actionKinds.indexOf('dismiss') < 0, 'fresh failed record has no dismissal control')
    view.row = Object.assign({}, view.row, {
      result: 'Native or explicitly reported failure reason',
      question: new Array(30).fill('Earlier question details').join('\n'),
      diagnostics: ''
    })
    t.step(50, function () {
      view.activateKind('inspect-failure', false)
      var result = t.findChild(view, 'reportedResult')
      t.check(result.y >= view.scroll.contentY && result.y + result.height <= view.scroll.contentY + view.scroll.height, 'failure inspection reveals the reported failure result')
      view.row = Object.assign({}, view.row, {
        result: '',
        diagnostics: 'Diagnostic-only failure reason'
      })
      t.step(50, function () {
        view.activateKind('inspect-failure', false)
        var diagnostics = t.findChild(view, 'reportedDiagnostics')
        t.check(diagnostics.y >= view.scroll.contentY && diagnostics.y + diagnostics.height <= view.scroll.contentY + view.scroll.height, 'failure inspection falls back to diagnostics without a result')
        staleFailureChecks()
      })
    })
  })

  // Local failure inspection preserves the existing stale-task action contract.
  function staleFailureChecks() {
    view.row = Object.assign({}, view.row, {
      canDismiss: true,
      freshnessLabel: 'Connection lost'
    })
    t.check(view.actionKinds.indexOf('dismiss') >= 0, 'owner-stale failure makes dismissal reachable')
    pointerIdentityChecks()
  }

  // Real press/release must never transfer an action to a new task or operation.
  function pointerIdentityChecks() {
    view.scroll.contentY = Math.max(0, view.scroll.contentHeight - view.scroll.height)
    t.step(400, function () {
      var control = t.findChildren(view, "taskAction").filter(function (c) {
        return c.modelData === "back"
      })[0]
      actions = []
      pointer.mousePress(control)
      t.check(control.pressedIdentity.length > 0, "real pointer press captures details identity")
      view.row = Object.assign({}, view.row, {
        key: "replacement-task"
      })
      t.step(400, function () {
        var current = t.findChildren(view, "taskAction").filter(function (c) {
          return c.modelData === "back"
        })[0]
        pointer.mouseRelease(current)
        t.equal(actions.length, 0, "press on old task cannot activate replacement after layout settles")
        pointer.mousePress(current)
        view.operation = {
          id: "replacement-operation",
          ownerId: "owner",
          taskId: "replacement-task",
          state: "completed",
          outcome: "observed"
        }
        t.step(400, function () {
          var next = t.findChildren(view, "taskAction").filter(function (c) {
            return c.modelData === "back"
          })[0]
          pointer.mouseRelease(next)
          t.equal(actions.length, 0, "press on old operation cannot activate new operation after layout settles")
          pointer.mouseClick(next)
          t.equal(actions.pop(), ["back", "replacement-task"], "settled fresh pointer action targets current task")
          t.done()
        })
      })
    })
  }
}
