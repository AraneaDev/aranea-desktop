// Actual production view/client with native subprocesses into a sandbox backend.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Settings

ShellRoot {
  id: root
  // Real sandbox registry/definition/run identities supplied by the shell acceptance.
  readonly property var data: JSON.parse(Quickshell.env('ARANEA_ACTION_FLOW_DATA'))
  // One native production handoff per newly opened observer host.
  readonly property string phase: Quickshell.env('ARANEA_ACTION_FLOW_PHASE')
  // Count native accepted signals independently of view selection.
  property int accepted: 0
  QmlTest {
    id: t
  }
  Settings.ProjectActions {
    id: actions
    width: 380
    displayOnly: true
    active: false
    project: root.data.project
    client.backendPath: Quickshell.env('ARANEA_ACTION_FLOW_ROOT') + '/scripts/aranea-project-actions'
    client.onRunAccepted: root.accepted++
  }
  // Await the actual asynchronous backend, with a bounded test deadline.
  function completed(fn) {
    t.waitFor(function () {
      return !actions.client.pending
    }, 15000, 'native backend completed', fn)
  }
  // Reattach a new production observer to the retained exact run.
  function inspect(fn) {
    t.check(actions.client.observeRun(data.runId), 'reopened client inspects retained exact ID')
    completed(function () {
      t.equal(actions.client.currentRun.id, data.runId, 'real backend returned retained run')
      fn()
    })
  }
  Component.onCompleted: t.step(100, function () {
    actions.displayOnly = false
    actions.client.refresh()
    t.waitFor(function () {
      return actions.client.snapshot.definitions.length > 0
    }, 10000, 'real saved definitions loaded', function () {
      var definition = actions.definitions.filter(function (d) {
        return d.id === data.actionId
      })[0]
      t.check(!!definition, 'public CLI configuration reaches production UI')
      t.equal(definition.argv[1], 'literal $HOME %i ; $(touch NEVER)', 'literal argument survives CLI/store/client handoff')
      if (phase === 'run' || phase === 'uncertain') {
        actions.client.checkAvailability()
        t.waitFor(function () {
          return actions.executionAvailable
        }, 10000, 'sandbox user manager available', function () {
          actions.selectAction(definition.id, definition.revision)
          t.equal(accepted, 0, 'selection and reads never submit')
          actions.activateAction(definition.id, definition.revision)
          completed(function () {
            var run = actions.client.currentRun
            t.check(actions.client.validRunIdentity(run), 'native acceptance includes opaque IDs revision and hash')
            t.equal(accepted, 1, 'one explicit Run retains acceptance')
            t.equal(run.checkoutId, data.project.lastCheckoutId, 'native Run uses exact selected checkout')
            t.equal(run.definitionSnapshot.argv, definition.argv, 'immutable accepted literal argv')
            t.equal(run.processState, phase === 'uncertain' ? 'unconfirmed' : 'running', 'actual manager process state')
            var receipt = actions.client.snapshot.requests.filter(function (r) {
              return r.requestId === actions.client.requestId
            })[0]
            t.equal(receipt.runId, run.id, 'exact generated receipt points to accepted run')
            t.check(!actions.client.start(definition.id, definition.revision), 'protected native acceptance refuses repeat submission')
            actions.client.disconnect()
            t.equal(actions.client.runId, run.id, 'closing observer retains acceptance identity')
            t.done()
          })
        })
      } else if (phase === 'logs-restart') {
        inspect(function () {
          t.check(actions.client.logs(data.runId), 'explicit native journal request')
          completed(function () {
            t.equal(actions.client.output, '<b>literal output</b>', 'real bounded journal reaches plaintext client')
            var output = t.findChild(actions, 'actionRunOutput')
            t.check(output && output.readOnly && output.selectByMouse && output.textFormat === TextEdit.PlainText, 'production output remains readonly selectable plaintext')
            t.check(actions.client.restart(data.runId), 'explicit guarded native Restart')
            completed(function () {
              t.check(actions.client.runId !== data.runId, 'Restart accepts a fresh opaque run ID')
              t.equal(actions.client.currentRun.processState, 'running', 'new run is observed running')
              t.equal(accepted, 1, 'Restart acceptance emitted once')
              t.done()
            })
          })
        })
      } else if (phase === 'recover-stop') {
        inspect(function () {
          t.check(actions.client.refreshRun(data.runId), 'reopened observer refreshes original run only')
          completed(function () {
            t.equal(actions.client.currentRun.processState, 'running', 'uncertain accepted unit adopted on refresh')
            t.check(!actions.client.currentRun.submissionUnconfirmed, 'adopted invocation clears uncertainty')
            t.check(actions.client.stop(data.runId), 'explicit Stop through actual client')
            completed(function () {
              t.equal(actions.client.currentRun.processState, 'stopped', 'Stop claims only observed terminal state')
              t.done()
            })
          })
        })
      } else if (phase === 'edit') {
        actions.editAction(definition.id, definition.revision)
        actions.editor.setField('name', 'Configured from production editor')
        actions.editor.save()
        completed(function () {
          t.check(!actions.editing, 'real configuration Save closes editor')
          t.equal(actions.definitions[0].name, 'Configured from production editor', 'production editor persists through actual backend')
          t.equal(accepted, 0, 'editor Save never accepts or launches a run')
          t.done()
        })
      } else {
        t.check(false, 'unknown acceptance phase')
        t.done()
      }
    })
  })
}
