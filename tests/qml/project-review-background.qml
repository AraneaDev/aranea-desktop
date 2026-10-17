// Marked task checkouts that are not selected are read in the background, one at a time.
import QtQuick
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Held review reads: {argv, done, answered}.
  property var calls: []
  QmlTest {
    id: t
  }
  Projects.ProjectReviewClient {
    id: client
    active: false
    projectId: 'p-a'
    checkoutId: 'x-p-a'
    backgroundInterval: 400
    backgroundTick: 50
    runner: function (argv, done) {
      host.calls.push({
        argv: argv,
        done: done,
        answered: false
      })
    }
  }
  FloatingWindow {
    visible: true
    implicitWidth: 400
    implicitHeight: 600
    Projects.ProjectsSidebar {
      id: sidebar
      width: 300
      height: 400
      reviews: host.markerReviews(client.reviews)
    }
  }
  // Helper data by checkout id, as the surface derives it for the sidebar.
  function markerReviews(all) {
    var out = {}
    Object.keys(all || {}).forEach(function (id) {
      if (all[id] && all[id].data)
        out[id] = all[id].data
    })
    return out
  }
  // Project with a primary checkout and a task checkout; marked ones carry a saved review mark.
  function project(id, marked) {
    return {
      id: id,
      name: id,
      lastCheckoutId: 'c-' + id,
      checkouts: [
        {
          id: 'c-' + id,
          path: '/work/' + id,
          branch: 'main',
          primary: true
        },
        {
          id: 'x-' + id,
          path: '/work/' + id + '-x',
          branch: 'feat/x',
          primary: false,
          review: marked ? {
            reviewedHead: 'a'.repeat(40),
            reviewedTaskAt: 100,
            reviewedAt: 200
          } : undefined
        }
      ]
    }
  }
  // A finished task on the project's task checkout.
  function task(id) {
    return {
      taskId: 't-' + id,
      reportedState: 'finished',
      lastReceivedAt: 100,
      association: {
        status: 'registered',
        projectId: id,
        checkoutId: 'x-' + id
      }
    }
  }
  // Review data for one project's task checkout.
  function data(id, head) {
    return {
      projectId: id,
      checkoutId: 'x-' + id,
      head: head,
      mergeBase: 'b'.repeat(40),
      commits: [],
      files: []
    }
  }
  // The project a held read names.
  function target(call) {
    return call.argv[3]
  }
  // Answer one held read with data for the project it names.
  function answer(call, head) {
    call.answered = true
    call.done(0, JSON.stringify({
      ok: true,
      data: host.data(host.target(call), head),
      error: null
    }), '')
  }
  Component.onCompleted: {
    Style.spacingScale = 1
    Style.spacingScaleWithFont = false
    var projects = [host.project('p-a', false), host.project('p-b', true)]
    sidebar.projects = projects
    sidebar.tasks = [host.task('p-a'), host.task('p-b')]
    client.tasks = sidebar.tasks
    client.projects = projects
    client.active = true
    t.waitFor(function () {
      return host.calls.length >= 1
    }, 3000, 'the selected checkout is read', function () {
      t.equal(host.target(host.calls[0]), 'p-a', 'the selected checkout is read first')
      t.step(200, function () {
        t.equal(host.calls.length, 1, 'only one read runs at a time')
        host.answer(host.calls[0], 'a'.repeat(40))
        t.waitFor(function () {
          return host.calls.length >= 2
        }, 3000, 'a marked checkout that is not selected is read in the background', backgroundRead)
      })
    })
  }
  // The background read returns a new head and the chip appears.
  function backgroundRead() {
    t.equal(host.target(host.calls[1]), 'p-b', 'the background read names the marked checkout')
    t.check(!t.findChild(sidebar, 'projectReviewChip:p-b').visible, 'no chip before the background read returns')
    host.answer(host.calls[1], 'd'.repeat(40))
    t.waitFor(function () {
      return t.findChild(sidebar, 'projectReviewChip:p-b').visible
    }, 3000, 'the chip appears when the background read returns a new head', function () {
      t.step(250, function () {
        t.equal(host.calls.length, 2, 'a background checkout is not read again inside its interval')
        closedFlow()
      })
    })
  }
  // Closing the window stops background reads.
  function closedFlow() {
    client.active = false
    t.step(800, function () {
      t.equal(host.calls.length, 2, 'no background read while the window is closed')
      client.active = true
      t.waitFor(function () {
        return host.calls.length >= 3
      }, 3000, 'reads resume when the window opens again', captureFlow)
    })
  }
  // Capture stops background reads.
  function captureFlow() {
    t.equal(host.target(host.calls[2]), 'p-a', 'the selected checkout is read again on reopening')
    host.answer(host.calls[2], 'a'.repeat(40))
    t.waitFor(function () {
      return host.calls.length >= 4
    }, 3000, 'the background read follows', function () {
      host.answer(host.calls[3], 'd'.repeat(40))
      client.captureActive = true
      t.step(800, function () {
        t.equal(host.calls.length, 4, 'no background read during capture')
        client.captureActive = false
        t.waitFor(function () {
          return host.calls.length >= 5
        }, 3000, 'reads resume after capture', selectedFirstFlow)
      })
    })
  }
  // A selected read waiting for the slot goes before another due background read.
  function selectedFirstFlow() {
    var held = host.calls[4]
    client.backgroundInterval = 100000
    var projects = [host.project('p-a', false), host.project('p-b', true), host.project('p-c', true)]
    client.tasks = [host.task('p-a'), host.task('p-b'), host.task('p-c')]
    client.projects = projects
    t.equal(host.target(held), 'p-b', 'a background read holds the slot')
    t.check(client.refreshSelected(), 'the selected read is queued behind it')
    var before = host.calls.length
    host.answer(held, 'd'.repeat(40))
    t.waitFor(function () {
      return host.calls.length > before
    }, 3000, 'the next read starts', function () {
      t.equal(host.target(host.calls[before]), 'p-a', 'the selected read beats a queued background read')
      host.answer(host.calls[before], 'a'.repeat(40))
      t.waitFor(function () {
        return host.calls.length > before + 1
      }, 3000, 'the background read follows', function () {
        t.equal(host.target(host.calls[before + 1]), 'p-c', 'the background read follows the selected read')
        capFlow()
      })
    })
  }
  // At most twelve checkouts are read in the background.
  function capFlow() {
    host.answer(host.calls[host.calls.length - 1], 'd'.repeat(40))
    var projects = [host.project('p-a', false)]
    var tasks = [host.task('p-a')]
    for (var i = 0; i < 15; i++) {
      var id = 'q' + i
      projects.push(host.project(id, true))
      tasks.push(host.task(id))
    }
    client.tasks = tasks
    client.projects = projects
    client.backgroundInterval = 600000
    t.equal(client.backgroundList().length, 12, 'the background list holds twelve checkouts')
    t.done()
  }
}
