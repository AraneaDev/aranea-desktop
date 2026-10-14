// Independent Projects navigation uses stable IDs and never hides an unsaved draft.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  TestCase {
    id: input
    name: 'navigationInput'
    when: false
  }
  // Serialized real client mutations captured without writing a registry.
  property var registryCalls: []
  // Held completion lets inspection race a pending metadata save.
  property var metadataDone: null
  // Owner transport calls must stay absent during inspection.
  property int ownerCalls: 0
  // Count actual Open signals even when the owner transport is inert.
  property int inspectionLaunches: 0
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
    entry.gitClient.captureActive = true
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
    entry.projectController.state = Object.assign({}, entry.projectController.state, {
      navigation: {
        lastProjectId: 'p-two',
        pinnedProjectIds: [],
        visitedAt: {}
      }
    })
    entry.projectId = ''
    entry.open('{}')
    t.equal(entry.projectId, 'p-two', 'saved registered selection is restored without a launch')
    var registered = entry.projectController.state
    entry.projectController.state = Object.assign({}, registered, {
      projects: [registered.projects[0]]
    })
    entry.open('{}')
    t.equal(entry.projectId, '', 'a removed saved selection reopens the recent project list')
    entry.projectController.state = registered
    t.check(surface.navigate('p-one'), 'standalone navigation selects the exact project')
    t.equal(entry.projectId, 'p-one', 'selection is independent of Settings')
    var page = t.findChild(surface, 'projectsPage')
    page.details.openRequested.connect(function (payload) {
      host.inspectionLaunches++
    })
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
    t.equal(sidebar.visibleProjectIds(), ['p-one', 'p-two'], 'background candidates include actual visible sidebar rows')
    t.equal(t.findChild(narrowSurface, 'projectsSidebar').visibleProjectIds(), [], 'hidden sidebar exposes no visible background rows')
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
      t.check(!t.findChild(narrowSurface, 'compactProjectSelector'), 'narrow navigation replaces the project dropdown')
      t.check(!!t.findChild(narrowSurface, 'projectPicker'), 'narrow navigation exposes the full searchable picker')
      host.inspectionLaunches = 0
      var picker = t.findChild(surface, 'projectPicker')
      t.findChild(header, 'headerChooseProject').activate()
      t.step(80, function () {
        t.check(picker.opened, 'selected narrow header opens full project search')
        input.keyClick(Qt.Key_Escape)
        t.check(!picker.opened && entry.opened, 'picker dismissal keeps Projects open')
        var checkoutPicker = t.findChild(header, 'checkoutPicker')
        entry.projectController.captureActive = false
        entry.projectController.runner = function (argv, payload, done) {
          host.registryCalls.push(JSON.parse(payload))
          host.metadataDone = done
        }
        entry.projectClient.runner = function (argv, done) {
          host.ownerCalls++
        }
        t.findChild(header, 'headerChooseCheckout').activate()
        t.step(80, function () {
          t.check(checkoutPicker.opened, 'header checkout selector is searchable')
          checkoutPicker.select('c-main')
          t.equal(host.registryCalls[0].action, 'select-checkout', 'checkout activation routes through the registry operation')
          t.equal(host.registryCalls[0].args, {
            projectId: 'p-one',
            checkoutId: 'c-main'
          }, 'checkout activation preserves exact project and checkout IDs')
          host.metadataDone(1, JSON.stringify({
            ok: false,
            error: {
              message: 'Metadata unavailable'
            }
          }), '')
          t.equal(host.ownerCalls, 0, 'project and checkout inspection emit no Open request')
          t.check(surface.navigate('p-two'), 'project inspection accepts navigation before saving metadata')
          t.check(entry.projectController.pending, 'visit metadata may be pending independently of selection')
          t.check(surface.navigate('p-one'), 'pending visit save cannot block inspecting another project')
          t.equal(entry.projectId, 'p-one', 'pending metadata preserves the new exact selected ID')
          t.findChild(surface, 'projectsSidebar').setupRequested()
          t.check(page.setupActive, 'metadata-only pending permits entering mandatory project setup')
          t.check(!page.setupNavigationPending, 'metadata-only pending cannot block wizard navigation')
          t.check(!entry.projectController.request('root-add', {
            path: '/work'
          }), 'metadata pending preserves serialization for native registry saves')
          page.finishSetup()
          t.check(!page.setupActive, 'metadata-only pending permits exiting clean project setup')
          host.metadataDone(1, JSON.stringify({
            ok: false,
            error: {
              message: 'Metadata unavailable'
            }
          }), '')
          t.equal(host.registryCalls[2] ? host.registryCalls[2].args : null, {
            projectId: 'p-one',
            visit: true
          }, 'latest navigation metadata is saved after a pending request fails')
          host.metadataDone(1, JSON.stringify({
            ok: false,
            error: {
              message: 'Metadata unavailable'
            }
          }), '')
          t.check(surface.navigate('p-two'), 'metadata save failure cannot block project inspection')
          host.metadataDone(1, JSON.stringify({
            ok: false,
            error: {
              message: 'Metadata unavailable'
            }
          }), '')
          surface.width = 1080
          var sidebar = t.findChild(surface, 'projectsSidebar')
          input.keyClick(Qt.Key_K, Qt.ControlModifier)
          t.check(t.findChild(sidebar, 'projectSearch').activeFocus, 'Ctrl+K focuses wide project search')
          var focus = window.activeFocusItem
          entry.projectController.state = Object.assign({}, entry.projectController.state)
          t.step(80, function () {
            t.equal(window.activeFocusItem === focus, true, 'registry refresh never steals the search field focus')
            t.equal(host.ownerCalls, 0, 'navigation and metadata failure never submit application launches')
            t.equal(host.inspectionLaunches, 0, 'project and checkout selection emit no Open signal')
            surface.chooseSection('preferences')
            var nameField = t.findChild(surface, 'projectNameDraft')
            t.check(!!nameField, 'preferences retain a normal name draft field')
            if (nameField) {
              nameField.forceActiveFocus()
              input.keyClick(Qt.Key_X)
              t.check(nameField.activeFocus && nameField.text.indexOf('x') >= 0, 'ordinary typed field text is not intercepted by project navigation')
              page.details.discardDraft()
            }
            t.done()
          })
        })
      })
    })
  })
}
