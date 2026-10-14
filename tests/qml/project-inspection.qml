// Exact-checkout bar inspection shares production draft guards without launching tools.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  QmlTest {
    id: t
  }
  Projects.ProjectsPresentation {
    id: entry
    windowEnabled: false
    captureActive: true
  }
  FloatingWindow {
    visible: true
    implicitWidth: 1080
    implicitHeight: 720
    Projects.ProjectsSurface {
      id: surface
      root: entry
      anchors.fill: parent
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
    entry.projectController.state = {
      projects: [
        {
          id: 'p-app',
          name: 'App',
          tools: {},
          workspaceMode: 'dedicated',
          lastCheckoutId: 'c-main',
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
          ]
        }
      ],
      roots: [],
      ignored: []
    }
    entry.projectId = 'p-app'
    entry.open(JSON.stringify({
      projectId: 'p-app',
      checkoutId: 'c-fix'
    }))
    t.equal(entry.selectedCheckoutId, 'c-fix', 'bar inspection chooses the exact associated checkout')
    t.equal(entry.projectController.state.projects[0].lastCheckoutId, 'c-main', 'inspection preserves the saved launch preference')
    t.equal(surface.overviewModel.checks.length, 0, 'inspection does not start a command')
    var page = t.findChild(surface, 'projectsPage')
    t.equal(page.selectedProject.lastCheckoutId, 'c-fix', 'header and details share the inspected checkout')
    page.details.setDraft('name', 'Unsaved')
    entry.open(JSON.stringify({
      projectId: 'p-app',
      checkoutId: 'c-main'
    }))
    t.equal(entry.selectedCheckoutId, 'c-fix', 'same-project checkout inspection cannot hide a draft')
    var guard = t.findChild(surface, 'projectDraftGuard')
    t.check(guard.opened, 'inspection offers the existing draft decision')
    guard.discardRequested()
    t.equal(entry.selectedCheckoutId, 'c-main', 'Discard continues to the exact retained checkout')
    entry.open(JSON.stringify({
      projectId: 'p-app',
      checkoutId: 'c-missing'
    }))
    t.equal(entry.selectedCheckoutId, 'c-main', 'deleted checkout inspection preserves the existing selection')
    t.check(!!entry.inspectionError, 'deleted checkout reports an inspection error')
    entry.captureActive = true
    t.equal(entry.open(JSON.stringify({
      projectId: 'p-app',
      checkoutId: 'c-fix'
    })), 'busy', 'capture refuses external inspection')
    t.equal(entry.selectedCheckoutId, 'c-main', 'capture does not change the inspected identity')
    t.done()
  })
}
