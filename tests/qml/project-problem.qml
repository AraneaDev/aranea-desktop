// The shared plain problem view: title, actions, Details and Copy, with capture and focus guards.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects
import "plugins/araneadev.projects/ProjectProblems.js" as Problems

ShellRoot {
  id: host
  // Texts handed to the clipboard runner.
  property var copied: []
  // Action ids emitted by the view.
  property var requested: []
  QmlTest {
    id: t
  }
  // Focus needs a real window.
  FloatingWindow {
    visible: true
    implicitWidth: 600
    implicitHeight: 400
    Projects.ProjectProblem {
      id: view
      width: 600
      clipboardRunner: function (text) {
        host.copied.push(text)
      }
      onActionRequested: function (id) {
        host.requested.push(id)
      }
      problem: Problems.problem({
        code: 'ACCEPTANCE_UNKNOWN',
        message: 'Launch acceptance is unknown.',
        recovery: 'Check launch status.'
      }, {
        surface: 'start',
        actions: ['checkAgain', 'startAnother']
      })
    }
  }
  Component.onCompleted: {
    var title = t.findChild(view, 'projectProblemTitle')
    t.equal(title.text, "Couldn't confirm it started", 'the title is the plain kind title')
    var check = t.findChild(view, 'projectProblemAction:checkAgain')
    var another = t.findChild(view, 'projectProblemAction:startAnother')
    t.check(!!check && check.visible, 'Check again is shown')
    t.check(!!another && another.visible, 'Start another is shown')
    check.clicked()
    t.equal(host.requested, ['checkAgain'], 'a click emits the action once')
    var details = t.findChild(view, 'projectProblemDetails')
    t.check(!details.visible, 'details start collapsed')
    t.findChild(view, 'projectProblemDetailsToggle').clicked()
    t.check(details.visible && details.text.indexOf('ACCEPTANCE_UNKNOWN') >= 0 && details.text.indexOf('Launch acceptance is unknown.') >= 0, 'details show the code and message')
    var copy = t.findChild(view, 'projectProblemCopy')
    copy.clicked()
    t.equal(host.copied, ['ACCEPTANCE_UNKNOWN: Launch acceptance is unknown. (Check launch status.)'], 'Copy sends the technical line')
    view.displayOnly = true
    t.check(!check.enabled && !another.enabled && !copy.enabled, 'capture disables actions and Copy')
    check.activate()
    another.activate()
    copy.activate()
    t.equal(host.requested, ['checkAgain'], 'capture emits nothing')
    t.equal(host.copied.length, 1, 'capture copies nothing')
    view.displayOnly = false
    t.waitFor(function () {
      view.focusPrimary()
      return check.activeFocus
    }, 3000, 'focusPrimary focuses the first action', function () {
      t.check(check.activeFocus, 'focusPrimary focuses the first action')
      view.problem = Problems.problem({
        code: 'X',
        message: 'm'
      }, {
        surface: 'start',
        actions: []
      })
      t.check(view.visible && !t.findChild(view, 'projectProblemAction:checkAgain'), 'a problem without actions shows no buttons')
      view.problem = null
      t.check(!view.visible, 'a null problem hides the view')
      t.done()
    })
  }
}
