// Exercise the real qs argument parser without touching the activity store.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "plugins/araneadev.activity" as Activity
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // IDs decoded by the isolated IPC receiver.
  property var received: null
  // Both scalar coercion and list expansion must preserve the array.
  property var batches: [['one'], ['first', 'second', 'third']]
  // Submit one case at a time through the real IPC parser.
  property int batch: 0
  QmlTest {
    id: t
  }
  Projects.ProjectRuntime {
    id: transport
  }
  IpcHandler {
    target: 'aranea.activity'
    function dismissMany(json: string): string {
      try {
        host.received = JSON.parse(json)
      } catch (e) {
        host.received = null
      }
      // End at the acceptance boundary: this fixture never removes tasks.
      return JSON.stringify({
        ok: false,
        error: {
          code: 'TEST_RECEIVED'
        }
      })
    }
  }
  Activity.ActivityClient {
    id: client
    runner: function (argv, done) {
      var config = decodeURIComponent(Qt.resolvedUrl('.').toString().replace(/^file:\/\//, ''))
      transport.run(['/usr/bin/qs', 'ipc', '-p', config, 'call', '--'].concat(argv.slice(1)), '', done)
    }
  }
  // Observe the receiver reply before submitting the next independent case.
  function submitNext() {
    received = null
    t.check(client.dismissMany(batches[batch]), 'batch submission starts')
    t.waitFor(function () {
      return !client.pending
    }, 3000, 'IPC reply received', function () {
      t.equal(received, batches[batch], 'all IDs arrive as one JSON string through qs')
      t.equal(client.error && client.error.code, 'TEST_RECEIVED', 'owner reply survives IPC argument parsing')
      batch++
      if (batch < batches.length)
        submitNext()
      else
        t.done()
    })
  }
  Component.onCompleted: t.step(300, submitNext)
}
