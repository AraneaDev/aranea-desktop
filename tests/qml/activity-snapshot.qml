// Large private replay histories must not overflow the presentation IPC payload.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.activity" as Activity
import "plugins/araneadev.agents" as Agents

ShellRoot {
  id: host
  // Every IPC reply the paged client read, to check each one fits the transport.
  property var replies: []
  QmlTest {
    id: t
  }
  // UTF-8 size of one IPC reply, the unit the transport limit is counted in.
  function bytes(value) {
    return unescape(encodeURIComponent(value)).length
  }
  // Answers the client from the in-process owner exactly as the IPC handler would.
  Activity.ActivityClient {
    id: client
    pollInterval: 60000
    runner: function (argv, done) {
      var reply = argv[2] === 'snapshot' ? JSON.stringify(owner.ipcSnapshot()) : argv[2] === 'snapshotPage' ? JSON.stringify(owner.ipcSnapshotPage(argv[3], Number(argv[4]))) : ''
      host.replies.push(reply)
      done(reply ? 0 : 1, reply, '')
    }
  }
  Agents.AgentTasks {
    id: view
    width: 320
    maxHeight: 500
    snapshot: client.snapshot
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
    paged()
  }
  // Many retained tasks with long reports reach the panel in bounded replies.
  function paged() {
    var long = 'Long reported result with words. '.repeat(124).slice(0, 4096)
    var tasks = [], sessions = []
    for (var i = 0; i < 300; i++) {
      var diagnostics = []
      for (var d = 0; d < 20; d++)
        diagnostics.push({
          summary: long,
          receivedAt: 900
        })
      tasks.push({
        taskId: 'claude:session-' + (i % 8) + ':prompt:' + i,
        provider: 'claude',
        providerSessionId: 'session-' + (i % 8),
        producerEpoch: 'epoch',
        reportedState: 'ready-for-review',
        description: 'Task ' + i + ' ' + long,
        result: long,
        question: '',
        blockers: [],
        diagnostics: diagnostics,
        verification: {
          status: 'unknown',
          summary: '',
          commands: []
        },
        association: {
          status: 'unassigned',
          projectId: null,
          checkoutId: null,
          cwd: '/home/user/work/checkout-' + i
        },
        lastReceivedAt: 900,
        source: 'native'
      })
    }
    for (var s = 0; s < 8; s++)
      sessions.push({
        provider: 'claude',
        providerSessionId: 'session-' + s,
        producerEpoch: 'epoch',
        connection: {
          connected: false,
          receivedAt: 900
        },
        provenance: null,
        nativeMetadata: {
          currentTaskId: null,
          turns: []
        }
      })
    owner.storeState = {
      schemaVersion: 1,
      revision: 11,
      tasks: tasks,
      sessions: sessions
    }
    t.check(bytes(JSON.stringify(owner.snapshot())) > 1000000, 'fixture is far larger than one IPC reply')
    client.refresh()
    t.check(host.replies.length > 1, 'large snapshot is read in several pages')
    t.check(host.replies.every(function (reply) {
      return reply && bytes(reply) < 64000
    }), 'every IPC reply stays under 64 KB')
    t.equal(client.snapshot.tasks.length, 300, 'client assembles every retained task')
    t.equal(client.snapshot.revision, 11, 'assembled snapshot keeps owner metadata')
    t.check(!client.snapshot.taskPage, 'paging bookkeeping is not part of the snapshot')
    t.equal(client.snapshot.tasks[299].result, long, 'full result kept for details')
    t.equal(view.taskRows.length, 300, 'panel lists every task')
    t.equal(owner.ipcSnapshotPage('stale-token', 1).error.code, 'SNAPSHOT_EXPIRED', 'unknown page token refused')
    boundedHeader()
  }
  // Many retained operations and a largest-size row still fit the first reply.
  function boundedHeader() {
    var wide = '€'.repeat(4096)
    var blockers = [], diagnostics = [], ops = []
    for (var b = 0; b < 32; b++)
      blockers.push({
        blockerId: 'b'.repeat(250) + b,
        question: wide
      })
    for (var d = 0; d < 20; d++)
      diagnostics.push({
        summary: wide,
        receivedAt: 900
      })
    var big = {
      taskId: 'x'.repeat(256),
      provider: 'claude',
      providerSessionId: 's'.repeat(256),
      producerEpoch: 'e'.repeat(256),
      reportedState: 'needs-input',
      description: wide,
      result: wide,
      question: wide,
      blockers: blockers,
      diagnostics: diagnostics,
      verification: {
        status: 'reported-fail',
        summary: wide,
        commands: Array(16).fill('c'.repeat(512))
      },
      association: {
        status: 'unassigned',
        projectId: null,
        checkoutId: null,
        cwd: '/' + 'p'.repeat(4000)
      },
      lastReceivedAt: 900,
      source: 'report'
    }
    for (var i = 0; i < 100; i++)
      ops.push({
        id: 'op-' + i,
        ownerId: owner.ownerId,
        taskId: 'task-' + i,
        action: 'reopen',
        state: 'completed',
        outcome: 'partial',
        attempt: 1,
        steps: [
          {
            role: 'terminal',
            status: 'observed',
            binding: {
              address: '0x' + 'a'.repeat(300)
            }
          }
        ],
        error: {
          code: 'SESSION_UNCONFIRMED',
          message: 'm'.repeat(600),
          recovery: 'r'.repeat(200)
        },
        task: big
      })
    owner.operations = ops
    owner.storeState = {
      schemaVersion: 1,
      revision: 12,
      tasks: [big],
      sessions: []
    }
    var first = JSON.stringify(owner.ipcSnapshot())
    t.check(bytes(first) < 64000, 'first reply with 100 retained operations and a largest row stays under 64 KB (' + bytes(first) + ')')
    t.check(JSON.parse(first).operations.length > 0, 'recent operation outcomes still reach the panel')
    owner.operations = []
    t.done()
  }
}
