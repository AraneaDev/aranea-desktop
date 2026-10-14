// Real registry client, with only external helper execution held at its boundary.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: root
  QmlTest {
    id: t
  }
  Component {
    id: clientComponent
    Projects.ProjectRegistryClient {}
  }
  // Create the real registry client with a deferred external helper boundary.
  function fixture() {
    var reads = []
    var client = clientComponent.createObject(root)
    client.storePath = '/fixture/store'
    client.toolsPath = '/fixture/tools'
    client.runner = function (argv, input, done) {
      reads.push({
        argv: argv,
        input: input,
        done: done
      })
    }
    return {
      client: client,
      reads: reads
    }
  }
  // Build an authoritative registry response at the requested revision.
  function snapshot(revision) {
    return JSON.stringify({
      ok: true,
      state: {
        schemaVersion: 2,
        revision: revision,
        roots: [
          {
            id: 'r-work',
            path: '/work'
          }
        ],
        ignored: [
          {
            path: '/work/ignored',
            commonDir: '/work/ignored/.git'
          }
        ],
        projects: [
          {
            id: 'p-demo',
            name: 'Demo',
            commonDir: '/work/demo/.git',
            lastCheckoutId: 'c-main',
            workspaceMode: 'dedicated',
            tools: {
              editorId: null,
              terminalId: null
            },
            associations: [],
            profiles: [],
            lastProfileId: null,
            environments: [],
            checkouts: [
              {
                id: 'c-main',
                path: '/work/demo',
                branch: 'main',
                primary: true
              }
            ]
          }
        ]
      }
    })
  }
  // Provide independent editor and terminal availability fixtures.
  function choices() {
    return JSON.stringify({
      defaults: {
        editorId: 'code',
        terminalId: 'foot'
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
          id: 'foot',
          label: 'Foot',
          available: true,
          supported: true
        }
      ]
    })
  }
  // Clearing shared error in a successful store callback loses an earlier tools failure.
  function failedTools(storeFirst) {
    var f = fixture(), client = f.client
    t.check(client.refresh(), 'refresh starts independent helper reads')
    t.equal(f.reads.map(function (read) {
      return [read.argv, read.input]
    }), [[['/fixture/store', 'snapshot'], ''], [['/fixture/tools', '--json'], '']], 'refresh uses fixed helper argv with empty stdin')
    t.check(!client.request('remove', {
      projectId: 'p-demo'
    }), 'mutation refused before either helper returns')
    var first = storeFirst ? 0 : 1, second = storeFirst ? 1 : 0
    function complete(index) {
      if (index === 0)
        f.reads[index].done(0, snapshot(7), '')
      else
        f.reads[index].done(1, '', 'Tool probe denied; check permissions and retry.')
    }
    complete(first)
    t.check(client.reading && !client.request('remove', {
      projectId: 'p-demo'
    }), 'mutation refused while the other helper remains unfinished')
    complete(second)
    t.check(!client.reading, 'read group completes in either callback order')
    t.check(client.error.indexOf('Tool probe denied') >= 0, 'tools failure survives successful store read in order ' + first + second)
    t.equal(client.state.revision, 7, 'successful store remains usable despite failed tool probe')
    t.equal(client.tools.editors, [], 'failed tool probe offers no unavailable choices')
    t.check(client.request('configure', {
      projectId: 'p-demo',
      name: 'Renamed'
    }), 'mutation allowed after both helpers finish')
    t.equal(JSON.parse(f.reads[2].input), {
      action: 'configure',
      args: {
        projectId: 'p-demo',
        name: 'Renamed'
      },
      expectedRevision: 7
    }, 'mutation uses successful registry readback revision')
    f.reads[2].done(0, snapshot(8), '')
    client.destroy()
  }
  // Error aggregation must not discard either independent failure or depend on timing.
  function dualFailure(storeFirst) {
    var f = fixture(), client = f.client
    client.error = 'Previous failure'
    client.refresh()
    function store() {
      f.reads[0].done(1, JSON.stringify({
        ok: false,
        error: {
          message: 'Registry locked.',
          recovery: 'Close the writer and retry.'
        }
      }), '')
    }
    function tools() {
      f.reads[1].done(1, '', 'Tools probe unavailable; retry.')
    }
    if (storeFirst) {
      store()
      tools()
    } else {
      tools()
      store()
    }
    t.check(client.error.indexOf('Registry locked.') >= 0 && client.error.indexOf('Close the writer and retry.') >= 0 && client.error.indexOf('Tools probe unavailable') >= 0, 'both failures include actionable recovery')
    var error = client.error
    client.destroy()
    return error
  }
  // A partial retry cannot clear an earlier failure before its independent probe finishes.
  function retry() {
    var f = fixture(), client = f.client
    client.error = 'Tools probe unavailable; retry.'
    client.refresh()
    f.reads[0].done(0, snapshot(12), '')
    t.check(!!client.error && client.reading, 'successful first retry helper retains error until group completion')
    f.reads[1].done(0, choices(), '')
    t.check(!client.reading && !client.error, 'fully successful retry clears old error')
    t.equal(client.tools.defaults, {
      editorId: 'code',
      terminalId: 'foot'
    }, 'retry supplies resolved supported tool defaults')
    client.destroy()
  }
  // Malformed or nonzero reads must never replace the known registry with defaults.
  function failedStore(code, output) {
    var f = fixture(), client = f.client
    client.state = JSON.parse(snapshot(21)).state
    client.refresh()
    f.reads[0].done(code, output, 'Registry transport failed; check storage and retry.')
    f.reads[1].done(0, choices(), '')
    t.equal(client.state.revision, 21, 'failed store read retains last durable revision')
    t.equal(client.state.projects[0].id, 'p-demo', 'failed store read preserves project identities')
    t.check(!!client.error && !client.reading, 'failed store read completes with actionable failure')
    client.destroy()
  }
  // Duplicate/stale callbacks must not release another read or roll back newer state.
  function staleCallbacks() {
    var f = fixture(), client = f.client
    client.refresh()
    f.reads[0].done(0, snapshot(1), '')
    f.reads[0].done(0, snapshot(0), '')
    t.check(client.reading, 'duplicate store callback cannot complete the tools half')
    t.equal(client.state.revision, 1, 'duplicate callback cannot replace first accepted readback')
    f.reads[1].done(0, choices(), '')
    client.refresh()
    f.reads[0].done(1, '', 'Late stale failure')
    t.check(client.reading && !client.error, 'superseded callback cannot affect newer read group')
    client.captureActive = true
    var count = f.reads.length
    t.check(!client.refresh() && !client.request('remove', {
      projectId: 'p-demo'
    }), 'capture refuses new helper work')
    f.reads[2].done(0, snapshot(99), '')
    client.captureActive = false
    f.reads[3].done(1, '', 'Capture callback failure')
    t.equal(client.state.revision, 1, 'capture rejects delayed durable readback')
    t.check(!client.error && f.reads.length === count, 'superseded capture callback cannot alter error after capture ends')
    client.destroy()
  }
  // Synchronous startup failure is still a completed failed helper, not a stuck read.
  function throwingRunner() {
    var f = fixture(), client = f.client
    client.runner = function (argv, input, done) {
      if (argv[0] === '/fixture/store')
        throw new Error('fixture spawn refused')
      f.reads.push({
        argv: argv,
        input: input,
        done: done
      })
    }
    var threw = false
    try {
      client.refresh()
    } catch (e) {
      threw = true
    }
    t.check(!threw, 'helper startup exception is reported without escaping refresh')
    t.equal(f.reads.length, 1, 'other refresh helper still runs after store startup exception')
    if (f.reads.length)
      f.reads[0].done(0, choices(), '')
    t.check(!client.reading && !!client.error, 'throwing read helper cannot wedge refresh')
    client.runner = function () {
      throw new Error('fixture mutation refused')
    }
    threw = false
    try {
      client.request('remove', {
        projectId: 'p-demo'
      })
    } catch (e) {
      threw = true
    }
    t.check(!threw && !client.pending && !!client.error, 'throwing mutation helper cannot wedge pending')
    client.destroy()
  }
  // Navigation metadata uses the same serialized, revision-aware store transport.
  function navigationMutation() {
    var f = fixture(), client = f.client
    client.state = JSON.parse(snapshot(7)).state
    var accepted = client.request('navigation-set', {
      projectId: 'p-demo',
      visit: true
    })
    t.check(accepted, 'navigation visit accepted by the internal registry client')
    t.equal(f.reads.length, 1, 'navigation creates exactly one store mutation')
    if (!accepted) {
      client.destroy()
      return
    }
    t.equal(f.reads[0].argv, ['/fixture/store', 'mutate'], 'navigation uses fixed store argv')
    t.equal(JSON.parse(f.reads[0].input), {
      action: 'navigation-set',
      args: {
        projectId: 'p-demo',
        visit: true
      },
      expectedRevision: 7
    }, 'visit sends identity with current revision and no caller timestamp')
    t.check(!client.request('navigation-set', {
      projectId: 'p-demo',
      pinned: true
    }), 'pin cannot race an in-flight visit')
    var visited = JSON.parse(snapshot(8))
    visited.state.navigation = {
      lastProjectId: 'p-demo',
      pinnedProjectIds: [],
      visitedAt: {
        'p-demo': 123
      }
    }
    f.reads[0].done(0, JSON.stringify(visited), '')
    t.equal(client.state.navigation, visited.state.navigation, 'visit saves authoritative navigation readback')
    t.check(!client.pending && !client.error, 'visit completes the mutation envelope')
    t.check(client.request('navigation-set', {
      projectId: 'p-demo',
      pinned: true
    }), 'pin accepted after visit completes')
    t.equal(JSON.parse(f.reads[1].input), {
      action: 'navigation-set',
      args: {
        projectId: 'p-demo',
        pinned: true
      },
      expectedRevision: 8
    }, 'pin uses the new durable revision')
    f.reads[1].done(1, JSON.stringify({
      ok: false,
      state: visited.state,
      error: {
        message: 'Registry changed.',
        recovery: 'Refresh and retry.'
      }
    }), '')
    t.equal(client.state, visited.state, 'failed navigation write retains readable project and navigation state')
    t.check(!client.pending && client.error.indexOf('Refresh and retry.') >= 0, 'navigation conflict releases pending with recovery')
    client.destroy()
  }
  // Presentation can save profiles, while all environment writes stay owner-controlled.
  function profileMutationBoundary() {
    var f = fixture(), client = f.client
    client.state = JSON.parse(snapshot(7)).state
    var args = {
      projectId: 'p-demo',
      profile: {
        name: 'Terminal',
        roles: ['terminal'],
        tools: {
          editorId: null,
          terminalId: 'kitty',
          agentId: null
        }
      }
    }
    var accepted = client.request('profile-save', args)
    t.check(accepted, 'profile save accepted by presentation registry client')
    if (accepted) {
      t.equal(JSON.parse(f.reads[0].input), {
        action: 'profile-save',
        args: args,
        expectedRevision: 7
      }, 'profile draft uses revision-aware fixed store transport')
      f.reads[0].done(0, snapshot(8), '')
      t.check(client.request('profile-remove', {
        projectId: 'p-demo',
        profileId: 'f-work',
        expectedProfileRevision: 1
      }), 'profile removal accepted after save readback')
      if (f.reads.length > 1)
        f.reads[1].done(0, snapshot(9), '')
    }
    var count = f.reads.length
    var ownerActions = ['environment-register', 'environment-associate', 'environment-forget']
    ownerActions.forEach(function (action) {
      t.check(!client.request(action, {
        projectId: 'p-demo'
      }), 'presentation refuses ' + action)
    })
    t.equal(f.reads.length, count, 'environment refusal creates no helper process')
    client.destroy()
  }
  Component.onCompleted: t.step(0, function () {
    failedTools(true)
    failedTools(false)
    t.equal(dualFailure(true), dualFailure(false), 'dual failures aggregate identically in both callback orders')
    retry()
    failedStore(0, 'not json')
    failedStore(0, JSON.stringify({
      ok: true,
      state: {
        roots: [],
        projects: []
      }
    }))
    failedStore(1, snapshot(99))
    staleCallbacks()
    throwingRunner()
    navigationMutation()
    profileMutationBoundary()
    t.done()
  })
}
