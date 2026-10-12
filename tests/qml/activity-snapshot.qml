// Large private replay histories must not overflow the presentation IPC payload.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.activity" as Activity

ShellRoot {
  QmlTest {
    id: t
  }
  Activity.ActivityController {
    id: owner
    captureActive: true
    clock: function () {
      return 1000000
    }
  }
  Component.onCompleted: {
    var receipts = [], callbacks = []
    for (var i = 0; i < 512; i++) {
      receipts.push({
        eventId: 'event-' + i,
        sequence: i + 1,
        hash: 'x'.repeat(200)
      })
      callbacks.push({
        key: 'key-' + i + 'x'.repeat(400),
        eventId: 'event-' + i,
        taskId: 'current'
      })
    }
    owner.storeState = {
      schemaVersion: 1,
      revision: 10,
      tasks: [
        {
          taskId: 'current',
          provider: 'codex',
          providerSessionId: 'thread',
          producerEpoch: 'epoch',
          reportedState: 'working',
          description: 'Current',
          association: {
            status: 'unassigned'
          }
        },
        {
          taskId: 'history',
          provider: 'codex',
          providerSessionId: 'thread',
          producerEpoch: 'epoch',
          reportedState: 'ready-for-review',
          association: {
            status: 'unassigned'
          }
        }
      ],
      sessions: [
        {
          provider: 'codex',
          providerSessionId: 'thread',
          producerEpoch: 'epoch',
          connection: {
            connected: true,
            receivedAt: 1000
          },
          provenance: {
            commandHash: 'verified'
          },
          receipts: receipts,
          registrationHash: 'private',
          retiredEpochs: ['private-epoch'],
          nativeMetadata: {
            currentTaskId: 'current',
            turns: [
              {
                nativeId: 'prompt:current',
                taskId: 'current'
              }
            ],
            observedHooks: ['SessionStart'],
            inactiveTaskIds: ['history'],
            callbackOwners: callbacks
          }
        }
      ]
    }
    var snapshot = owner.snapshot()
    t.check(JSON.stringify(snapshot).length < 100000, 'IPC snapshot excludes oversized replay bookkeeping')
    t.check(!snapshot.sessions[0].receipts && !snapshot.sessions[0].nativeMetadata.callbackOwners, 'private receipt and callback histories stay in owner')
    t.equal(snapshot.tasks.length, 2, 'all task history retained in presentation')
    t.equal(snapshot.tasks[0].freshness, 'connected', 'native eligibility projected before private metadata removal')
    t.equal(snapshot.tasks[1].freshness, 'connection-lost', 'inactive task projection retained')
    t.equal(snapshot.sessions[0].nativeMetadata.currentTaskId, 'current', 'current thread metadata retained')
    t.equal(owner.storeState.sessions[0].receipts.length, 512, 'authoritative replay receipts unchanged')
    t.equal(owner.storeState.sessions[0].nativeMetadata.callbackOwners.length, 512, 'authoritative callback correlation unchanged')
    t.done()
  }
}
