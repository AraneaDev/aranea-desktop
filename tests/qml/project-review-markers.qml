// The Review chip shows in the sidebar only for projects with a task checkout ready to review.
import QtQuick
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.projects" as Projects
import "plugins/araneadev.projects/ProjectProblems.js" as Problems

ShellRoot {
  id: host
  QmlTest {
    id: t
  }
  FloatingWindow {
    visible: true
    implicitWidth: 400
    implicitHeight: 600
    Projects.ProjectsSidebar {
      id: sidebar
      width: 300
      height: 400
    }
  }
  // Project with a primary checkout and one task checkout.
  function project(id, name) {
    return {
      id: id,
      name: name,
      lastCheckoutId: 'c-' + id,
      checkouts: [
        {
          id: 'c-' + id,
          path: '/work/' + name,
          branch: 'main',
          primary: true
        },
        {
          id: 'x-' + id,
          path: '/work/' + name + '-x',
          branch: 'feat/x',
          primary: false
        }
      ]
    }
  }
  // An agent task on the task checkout of a project.
  function task(id, state) {
    return {
      taskId: 't-' + id,
      reportedState: state,
      lastReceivedAt: 100,
      association: {
        status: 'registered',
        projectId: id,
        checkoutId: 'x-' + id
      }
    }
  }
  Component.onCompleted: {
    Style.spacingScale = 1
    Style.spacingScaleWithFont = false
    sidebar.projects = [host.project('p-a', 'Aye'), host.project('p-b', 'Bee'), host.project('p-c', 'Cee')]
    sidebar.tasks = [host.task('p-a', 'ready-for-review'), host.task('p-b', 'working')]
    t.step(80, function () {
      var a = t.findChild(sidebar, 'projectReviewChip:p-a')
      t.check(!!a && a.visible, 'a project with a ready task checkout shows the chip')
      t.equal(a.text, 'Review', 'the chip reads Review')
      var b = t.findChild(sidebar, 'projectReviewChip:p-b')
      t.check(!!b && !b.visible, 'a working task shows no chip')
      var c = t.findChild(sidebar, 'projectReviewChip:p-c')
      t.check(!!c && !c.visible, 'a project without tasks shows no chip')
      sidebar.tasks = [host.task('p-a', 'finished'), host.task('p-b', 'failed')]
      t.step(40, function () {
        t.check(t.findChild(sidebar, 'projectReviewChip:p-b').visible, 'a failed task is also ready for review')
        var mark = host.project('p-a', 'Aye')
        mark.checkouts[1].review = {
          reviewedHead: 'a'.repeat(40),
          reviewedTaskAt: 100,
          reviewedAt: 200
        }
        sidebar.projects = [mark, host.project('p-b', 'Bee'), host.project('p-c', 'Cee')]
        sidebar.reviews = {
          'x-p-a': {
            head: 'a'.repeat(40)
          }
        }
        t.step(40, function () {
          t.check(!t.findChild(sidebar, 'projectReviewChip:p-a').visible, 'a reviewed checkout loses the chip')
          var text = t.findChild(sidebar, 'projectReviewChip:p-b').text
          t.check(!Problems.bannedIn(text) && text.indexOf(String.fromCharCode(8212)) < 0, 'chip text has no banned word or em dash')
          t.done()
        })
      })
    })
  }
}
