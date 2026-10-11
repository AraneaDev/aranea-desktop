// Independent Projects navigation uses stable IDs and never hides an unsaved draft.
import QtQuick
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  QmlTest {
    id: t
  }
  Projects.ProjectsPresentation {
    id: entry
    windowEnabled: false
  }
  Projects.Projects {
    id: inertEntry
    windowEnabled: false
    captureActive: true
  }
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 1080
    implicitHeight: 720
    Projects.ProjectsSurface {
      id: surface
      anchors.fill: parent
      root: entry
    }
  }
  Projects.ProjectsSurface {
    id: narrowSurface
    width: 420
    height: 620
    root: entry
    visible: false
  }
  Component.onCompleted: t.step(80, function () {
    Style.spacingScale = 1
    Style.spacingScaleWithFont = false
    entry.activityClient.captureActive = true
    var presentation = t.findChildren(inertEntry, '').filter(function (item) {
      return typeof item.captureBegin === 'function'
    })[0]
    t.check(!!presentation, 'owner composition exposes independent presentation')
    t.check(!presentation.projectController.request('remove', {
      projectId: 'p-one'
    }), 'inert owner composition refuses registry mutations')
    t.equal(inertEntry.open('{}'), 'busy', 'inert owner composition refuses live presentation reads')
    entry.view = surface
    entry.projectController.captureActive = true
    entry.projectClient.captureActive = true
    entry.discoveryClient.captureActive = true
    entry.projectController.state = {
      roots: [],
      ignored: [],
      projects: [
        {
          id: 'p-one',
          name: 'Alpha',
          tools: {},
          workspaceMode: 'dedicated',
          checkouts: [],
          lastCheckoutId: ''
        },
        {
          id: 'p-two',
          name: 'Beta',
          tools: {},
          workspaceMode: 'dedicated',
          checkouts: [],
          lastCheckoutId: ''
        }
      ]
    }
    t.check(surface.navigate('p-one'), 'standalone navigation selects the exact project')
    t.equal(entry.projectId, 'p-one', 'selection is independent of Settings')
    var page = t.findChild(surface, 'projectsPage')
    page.details.actions.client.captureActive = true
    page.details.setDraft('name', 'Unsaved')
    t.check(!surface.navigate('p-two'), 'unsaved preferences prevent changing project')
    t.equal(entry.projectId, 'p-one', 'refusal preserves selected identity')
    page.details.discardDraft()
    page.details.actions.editing = true
    t.check(!surface.navigate('p-two'), 'action editor prevents hiding an unsaved draft')
    surface.section = 'actions'
    t.check(surface.navigate('p-one') && surface.section === 'actions', 'same-project selection preserves an action draft destination')
    page.details.actions.editing = false
    t.check(surface.navigate('p-two'), 'clean selection can switch to another project')
    t.equal(entry.projectId, 'p-two', 'switch chooses identity rather than list position')
    t.check(!surface.navigate('p-missing'), 'unknown project identity is refused')
    var sidebar = t.findChild(surface, 'projectsSidebar')
    sidebar.query = 'alpha'
    t.equal(sidebar.filteredProjects.map(function (p) {
      return p.id
    }), ['p-one'], 'sidebar searches registered project names')
    t.check(!t.findChild(surface, 'settingsNavigation'), 'Projects has its own navigation')
    t.check(surface.chooseSection('actions'), 'project Actions destination is available')
    t.equal(surface.section, 'actions', 'workflow destination has explicit state')
    t.check(surface.chooseSection('agents'), 'project Agents destination is available')
    entry.close()
    t.equal(entry.projectId, 'p-two', 'closing presentation retains project selection')
    t.equal(entry.open('{}'), 'ok', 'reopening the project manager succeeds')
    t.equal(entry.projectId, 'p-two', 'reopening restores the last selected project')
    page.details.setDraft('name', 'Keep this draft')
    entry.close()
    t.equal(entry.open('{}'), 'ok', 'reopening the same project preserves an unsaved draft')
    t.equal(page.details.draft.name, 'Keep this draft', 'reopening never discards project preferences')
    page.details.discardDraft()
    t.check(surface.navigate(''), 'welcome is reachable without a selected project')
    t.check(t.findChild(surface, 'projectsWelcome').visible, 'unselected manager offers guidance instead of a blank page')
    t.findChild(surface, 'welcomeAddProject').activate()
    t.check(page.setupActive, 'welcome Add project enters the existing setup wizard')
    page.finishSetup()
    t.check(surface.navigate('p-one'), 'project selection returns from welcome')
    t.check(!t.findChild(surface, 'projectSetupStart').visible, 'project destinations do not repeat setup controls')
    t.check(surface.chooseSection('preferences'), 'folder management is reachable through Preferences')
    t.findChild(surface, 'projectFoldersToggle').activate()
    t.check(page.foldersExpanded, 'Preferences reveals existing discovery folder management')
    page.foldersExpanded = false
    entry.projectClient.snapshot = {
      availability: {
        compositor: true
      },
      bindings: [],
      operations: []
    }
    entry.projectClient.available = true
    t.check(surface.chooseSection('agents'), 'Agents remains reachable after preferences')
    t.findChild(surface, 'projectPrimaryOpen').activate()
    t.equal(surface.section, 'overview', 'Open from Agents reveals the destination containing its outcome and recovery controls')
    entry.projectController.state = Object.assign({}, entry.projectController.state, {
      projects: entry.projectController.state.projects.map(function (p) {
        return p.id === 'p-one' ? Object.assign({}, p, {
          lastCheckoutId: 'c-main',
          checkouts: [
            {
              id: 'c-main',
              path: '/repo',
              branch: 'feature/' + 'customer-dashboard-and-developer-accessibility-improvements-'.repeat(8)
            }
          ]
        }) : p
      })
    })
    surface.width = 420
    t.step(80, function () {
      var header = t.findChild(surface, 'projectHeader'), branch = t.findChild(header, 'projectBranch')
      t.check(branch.width <= header.width && branch.height > 0, 'long branch metadata stays readable inside the compact viewport')
      t.check(narrowSurface.compact, 'standalone layout adapts to narrow widths')
      t.done()
    })
  })
}
