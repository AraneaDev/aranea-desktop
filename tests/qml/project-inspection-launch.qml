// Explicit launch from inspection waits for selected-checkout readback and retains its target.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Held registry mutations make selection readback and failure observable.
  property var mutations: []
  // Native owner requests retain exact identities without executing tools.
  property var launches: []
  QmlTest {
    id: t
  }
  Projects.ProjectsPresentation {
    id: entry
    windowEnabled: false
    captureActive: true
  }
  Projects.ProjectsSurface {
    id: surface
    root: entry
    width: 1080
    height: 720
  }
  // Fixed registry readback contains both worktrees and the displayed profile revision.
  function state(checkout) {
    return {
      roots: [],
      ignored: [],
      projects: [
        {
          id: 'p-app',
          name: 'App',
          tools: {},
          workspaceMode: 'dedicated',
          lastCheckoutId: checkout,
          checkouts: [
            {
              id: 'c-main',
              path: '/app',
              branch: 'main'
            },
            {
              id: 'c-fix',
              path: '/app-fix',
              branch: 'fix'
            }
          ],
          profiles: [
            {
              id: 'f-work',
              name: 'Work',
              revision: 1,
              roles: ['terminal'],
              tools: {
                terminalId: 'kitty'
              }
            }
          ],
          lastProfileId: 'f-work'
        }
      ]
    }
  }
  Component.onCompleted: t.step(80, function () {
    entry.view = surface
    entry.captureActive = false
    entry.projectController.captureActive = true
    entry.projectClient.captureActive = true
    entry.activityClient.captureActive = true
    entry.gitClient.captureActive = true
    entry.actionClient.captureActive = true
    entry.projectController.state = state('c-main')
    entry.projectId = 'p-app'
    entry.open(JSON.stringify({
      projectId: 'p-app',
      checkoutId: 'c-fix'
    }))
    entry.projectController.runner = function (argv, input, done) {
      host.mutations.push({
        payload: JSON.parse(input || '{}'),
        done: done
      })
    }
    entry.projectController.captureActive = false
    entry.projectClient.captureActive = false
    entry.projectClient.identityRunner = function (done) {
      done('00000000-0000-4000-8000-000000000033')
    }
    entry.projectClient.runner = function (argv, done) {
      host.launches.push({
        method: argv[2],
        payload: JSON.parse(argv[3] || '{}')
      })
      done(0, JSON.stringify({
        ok: false,
        error: {
          code: 'TEST_REFUSAL',
          message: 'Inert owner'
        }
      }), '')
    }
    t.check(entry.startProfile('f-work', 1, false), 'explicit Start accepts checkout selection before launch')
    t.equal(host.mutations.length, 1, 'inspected profile launch selects its checkout exactly once')
    t.equal(host.mutations[0].payload.args, {
      projectId: 'p-app',
      checkoutId: 'c-fix'
    }, 'selection uses exact displayed checkout')
    t.equal(host.launches.length, 0, 'profile launch waits for authoritative registry readback')
    t.check(!entry.startProfile('f-work', 1, false), 'pending selection prevents duplicate Start')
    host.mutations[0].done(0, JSON.stringify({
      ok: true,
      state: state('c-fix')
    }), '')
    t.equal(host.launches.length, 1, 'successful selection starts the frozen profile once')
    t.equal(host.launches[0].payload.checkoutId, 'c-fix', 'profile owner receives inspected checkout')
    t.equal(host.launches[0].payload.profileId, 'f-work', 'profile identity survives selection readback')
    entry.projectController.state = state('c-main')
    surface.inspectCheckout('p-app', 'c-fix')
    entry.startProfile('f-work', 1, false)
    host.mutations[1].done(1, JSON.stringify({
      ok: false,
      error: {
        message: 'Checkout selection failed'
      }
    }), '')
    t.equal(host.launches.length, 1, 'failed selection never launches the profile')
    t.equal(entry.selectedCheckoutId, 'c-fix', 'failed selection preserves inspection')
    entry.startProfile('f-work', 1, false)
    entry.close()
    host.mutations[2].done(0, JSON.stringify({
      ok: true,
      state: state('c-fix')
    }), '')
    t.equal(host.launches.length, 1, 'closing before selection completes prevents a later launch')
    entry.projectController.state = state('c-main')
    entry.opened = true
    surface.inspectCheckout('p-app', 'c-fix')
    var page = t.findChild(surface, 'projectsPage')
    page.details.agentChoice = {
      suggestedId: 'codex',
      options: [
        {
          id: 'codex',
          available: true,
          supported: true
        }
      ]
    }
    page.details.openAvailable = true
    page.details.startAgent('codex')
    t.equal(host.launches.length, 2, 'explicit agent Start routes through the existing owner')
    t.equal(host.launches[1].method, 'request', 'agent Start uses the existing operation contract')
    t.equal(host.launches[1].payload.checkoutId, 'c-fix', 'agent Start retains the inspected checkout rather than the saved preference')
    t.equal(host.launches[1].payload.agentId, 'codex', 'explicit agent identity remains unchanged')
    page.openRequested({
      projectId: 'p-app',
      checkoutId: 'c-main'
    })
    t.equal(host.launches[2].payload.checkoutId, 'c-main', 'explicit checkout-row Open is not retargeted by inspection')
    page.openRequested({
      projectId: 'p-app',
      checkoutId: 'c-main',
      retryRole: 'editor'
    })
    t.equal(host.launches[3].payload.checkoutId, 'c-main', 'exact recovery retains its original checkout during inspection')
    t.equal(host.launches[3].payload.retryRole, 'editor', 'recovery retains its original role')
    t.done()
  })
}
