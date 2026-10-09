// Inert details/actions tests for exact task identities and retained outcomes.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.agents" as Agents
import "plugins/araneadev.agents/AgentTasksLogic.js" as Logic

ShellRoot {
  id: host
  // View actions are recorded without invoking clients.
  property var actions: []
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
      canDismiss: true,
      freshnessLabel: 'Connection lost'
    })
    t.check(view.actionKinds.indexOf('dismiss') >= 0, 'owner-stale failure makes dismissal reachable')
    t.done()
  })
}
