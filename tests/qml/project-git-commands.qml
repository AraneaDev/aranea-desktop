// A held runner exercises the command client's single slot and capture guard.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Only the external helper boundary is replaced; the client logic stays real.
  property var calls: []
  // Records {operation, response} from each finished signal.
  property var seen: []
  QmlTest {
    id: t
  }
  Projects.ProjectGitCommands {
    id: commands
    backendPath: '/fixture/aranea-project-git'
    watchdogInterval: 120
    runner: function (argv, done) {
      host.calls.push({
        argv: argv,
        done: done
      })
    }
    onFinished: function (operation, projectId, checkoutId, response) {
      host.seen.push({
        operation: operation,
        response: response
      })
    }
  }
  Component.onCompleted: {
    t.check(commands.run('fetch', 'p-1', 'c-1', []), 'an idle client accepts a run')
    t.equal(calls[0].argv.slice(1), ['fetch', '--project', 'p-1', '--checkout', 'c-1', '--json'], 'argv carries exact IDs')
    t.equal(commands.pending.operation, 'fetch', 'the accepted run is pending')
    t.check(!commands.run('pull', 'p-1', 'c-1', []), 'a second run is refused while pending')
    t.equal(calls.length, 1, 'a refused run starts nothing')
    calls[0].done(0, '{"ok":true,"data":{"remote":"origin"},"error":null}', '')
    t.equal(seen.length, 1, 'finished is emitted once')
    t.check(seen[0].response.ok === true, 'finished carries the parsed envelope')
    t.check(commands.pending === null, 'pending clears on completion')
    t.equal(commands.resultFor('fetch', 'p-1', 'c-1').data.remote, 'origin', 'the result is kept by key')
    commands.clear('fetch', 'p-1', 'c-1')
    t.check(commands.resultFor('fetch', 'p-1', 'c-1') === null, 'clear forgets the result')
    t.check(!commands.run('fetch', '', 'c-1', []), 'a missing ID is refused')
    t.check(commands.run('pull', 'p-1', 'c-1', []), 'the next run is accepted')
    calls[1].done(1, 'nope', 'boom')
    t.equal(seen[1].response.error.code, 'READ_FAILED', 'malformed output is a read failure')
    t.equal(seen[1].response.error.message, 'boom', 'diagnostics become the message')
    t.check(commands.run('task-create', 'p-1', 'c-1', ['--branch', 'feat/x']), 'a create run is accepted')
    t.equal(calls[2].argv.slice(1), ['task-create', '--project', 'p-1', '--checkout', 'c-1', '--branch', 'feat/x', '--json'], 'extra items come before --json')
    calls[2].done(0, '{"ok":true,"data":{},"error":null}', '')
    t.check(commands.run('pull', 'p-1', 'c-1', []), 'a run that will never answer is accepted')
    t.step(400, watchdogChecks)
  }
  // Catch a helper that never answers leaving the slot taken forever, or a late answer overriding the timeout.
  function watchdogChecks() {
    t.equal(seen.length, 4, 'the watchdog emits finished once')
    t.equal(seen[3].response.error.code, 'GIT_TIMEOUT', 'the watchdog reports a timeout')
    t.check(seen[3].response.ok === false && seen[3].response.error.recovery === 'Retry.', 'the timeout carries a recovery')
    t.check(commands.pending === null, 'the watchdog frees the slot')
    calls[3].done(0, '{"ok":true,"data":{},"error":null}', '')
    t.equal(seen.length, 4, 'a late completion after the timeout is ignored')
    t.equal(commands.resultFor('pull', 'p-1', 'c-1').error.code, 'GIT_TIMEOUT', 'the late completion keeps the timeout result')
    t.check(commands.run('fetch', 'p-1', 'c-1', []), 'the slot accepts a new run after the timeout')
    calls[4].done(0, '{"ok":true,"data":{},"error":null}', '')
    t.step(300, function () {
      t.equal(seen.length, 5, 'a finished run never also times out')
      captureChecks()
    })
  }
  // Catch capture leaving work running or accepting late completions.
  function captureChecks() {
    t.check(commands.run('task-remove', 'p-1', 'c-1', ['--check']), 'a remove check is accepted')
    commands.captureActive = true
    t.check(commands.pending === null, 'capture clears pending')
    calls[5].done(0, '{"ok":true,"data":{},"error":null}', '')
    t.equal(seen.length, 5, 'a late completion emits nothing')
    t.check(!commands.run('fetch', 'p-1', 'c-1', []), 'capture refuses runs')
    t.equal(calls.length, 6, 'capture starts nothing')
    t.done()
  }
}
