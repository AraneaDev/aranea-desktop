// Actual surface/client integration retains profiles until authoritative guarded saves succeed.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Record real client requests at the controlled transport boundary.
  property var requests: []
  // Count read-only tool refreshes separately from configuration.
  property int toolReads: 0
  // Held acknowledgements exercise revision conflicts and navigation.
  property var callbacks: []
  QmlTest {
    id: t
  }
  Projects.ProjectsPresentation {
    id: entry
    windowEnabled: false
  }
  FloatingWindow {
    visible: true
    width: 900
    height: 700
    Projects.ProjectsSurface {
      id: surface
      anchors.fill: parent
      root: entry
    }
  }
  Component.onCompleted: t.step(80, function () {
    entry.projectController.runner = function (argv, input, done) {
      if (!input) {
        if (argv[argv.length - 1] === '--json') {
          host.toolReads++
          done(0, JSON.stringify(entry.projectController.tools), '')
        } else
          done(0, JSON.stringify({
            ok: true,
            state: entry.projectController.state
          }), '')
        return
      }
      var request = JSON.parse(input)
      if (request.action === 'navigation-set')
        done(0, JSON.stringify({
          ok: true,
          state: entry.projectController.state
        }), '')
      else {
        host.requests.push(request)
        host.callbacks.push(done)
      }
    }
    entry.projectClient.runner = function () {}
    entry.gitClient.runner = function () {}
    entry.actionClient.runner = function () {}
    var saved = {
      id: 'f-one',
      revision: 3,
      name: '<b>Work</b>',
      roles: ['editor'],
      tools: {
        editorId: 'code',
        terminalId: null,
        agentId: null
      }
    }
    var project = {
      id: 'p-one',
      name: 'One',
      tools: {},
      profiles: [saved],
      lastCheckoutId: 'c-one',
      checkouts: [
        {
          id: 'c-one',
          path: '/fixture/one'
        }
      ],
      environments: [
        {
          profileSnapshot: saved
        }
      ]
    }
    entry.projectController.tools = {
      defaults: {
        editorId: 'code'
      },
      editors: [
        {
          id: 'code',
          label: 'VS Code',
          available: true,
          supported: true
        }
      ],
      terminals: [],
      agents: []
    }
    entry.projectController.state = {
      revision: 9,
      projects: [project],
      roots: [],
      ignored: []
    }
    entry.projectId = project.id
    entry.view = surface
    var page = t.findChild(surface, 'projectsPage')
    t.check(typeof page.details.beginProfile === 'function', 'profile management exists in production Details')
    if (typeof page.details.beginProfile !== 'function') {
      t.done()
      return
    }
    surface.chooseSection('profiles')
    var name = t.findChild(page.details, 'profileName:f-one')
    t.check(!!name && name.text === '<b>Work</b>' && name.textFormat === Text.PlainText, 'saved names are literal plain text')
    t.check(!t.findChild(page.details, 'profilePresetChoices').visible, 'optional new-profile choices stay behind Add profile')
    t.findChild(page.details, 'addProfile').activate()
    t.check(t.findChild(page.details, 'profilePresetChoices').visible, 'Add profile reveals usable presets and custom selection')
    t.check(!t.findChild(surface, 'headerManageProfiles').visible, 'Profiles destination omits redundant management navigation')
    page.details.beginProfile(saved)
    page.details.profileEditor.setName('Changed')
    var refresh = t.findChild(page.details, 'profileRefreshTools')
    t.check(!!refresh && refresh.enabled, 'missing tools have a direct refresh recovery')
    if (refresh)
      refresh.activate()
    t.equal(toolReads, 1, 'profile recovery probes tools through the existing read client')
    t.equal(page.details.profileEditor.draft.name, 'Changed', 'tool refresh retains profile draft')
    var back = t.findChild(page.details, 'profileListReturn')
    t.check(!!back && back.enabled, 'profile list remains reachable during editing')
    if (back)
      back.activate()
    var internalGuard = t.findChild(surface, 'projectDraftGuard')
    t.check(internalGuard.opened, 'return to saved or new profile choices uses draft guard')
    internalGuard.keepEditingRequested()
    surface.chooseSection('overview')
    var guard = t.findChild(surface, 'projectDraftGuard')
    t.check(guard.opened && surface.section === 'profiles', 'profile draft invokes shared navigation decision')
    guard.keepEditingRequested()
    entry.close()
    t.check(page.details.profileEditing, 'close retains profile draft')
    var before = page.captureSnapshot()
    page.captureReset({})
    page.captureRestore(before)
    t.equal(page.details.profileEditor.draft.name, 'Changed', 'capture preserves profile draft and revision')
    t.equal(page.details.profileEditor.expectedProfileRevision, 3, 'capture preserves original profile edit revision')
    surface.chooseSection('overview')
    page.details.profileEditor.setName(' ')
    guard.saveRequested()
    t.check(guard.opened && !!guard.error && requests.length === 0, 'invalid Save retains navigation and actionable feedback')
    page.details.profileEditor.setName('Changed')
    guard.saveRequested()
    t.equal(requests[0].expectedRevision, 9, 'save uses current registry concurrency guard')
    t.equal(requests[0].args.expectedProfileRevision, 3, 'save uses original profile revision')
    callbacks.shift()(1, JSON.stringify({
      ok: false,
      error: {
        message: 'Profile changed; reload or discard.'
      }
    }), '')
    t.check(page.details.profileEditing && guard.opened && surface.section === 'profiles', 'conflict retains draft and pending destination')
    guard.saveRequested()
    var updated = Object.assign({}, saved, {
      name: 'Changed',
      revision: 4
    })
    project = Object.assign({}, project, {
      profiles: [updated]
    })
    callbacks.shift()(0, JSON.stringify({
      ok: true,
      state: {
        revision: 10,
        projects: [project],
        roots: [],
        ignored: []
      }
    }), '')
    t.step(40, function () {
      t.check(!page.details.profileEditing && surface.section === 'overview', 'matching successful acknowledgement continues navigation')
      t.equal(project.environments[0].profileSnapshot.name, '<b>Work</b>', 'profile edits leave old launch snapshot untouched')
      surface.chooseSection('profiles')
      page.details.removeProfile(updated)
      t.equal(requests[2].args, {
        projectId: 'p-one',
        profileId: 'f-one',
        expectedProfileRevision: 4
      }, 'remove targets exact saved profile revision')
      callbacks.shift()(1, JSON.stringify({
        ok: false,
        error: {
          message: 'Profile changed'
        }
      }), '')
      t.equal(page.selectedProject.profiles.length, 1, 'failed removal retains saved profile')
      page.details.beginProfile(updated)
      surface.chooseSection('overview')
      page.details.profileEditor.fieldError = 'Invalid discarded profile'
      guard.discardRequested()
      t.equal(page.details.profileEditor.fieldError, '', 'Discard clears stale profile field validation')
      t.check(!page.details.profileEditing && surface.section === 'overview', 'Discard restores navigation without a mutation')
      entry.projectController.state = {
        revision: 11,
        projects: [Object.assign({}, project, {
            profiles: []
          })],
        roots: [],
        ignored: []
      }
      t.check(t.findChild(surface, 'headerManageProfiles').visible, 'CLI zero-profile registration has direct setup recovery')
      t.equal(requests.length, 3, 'ordinary refresh does not persist presets')
      page.startSetup()
      page.setupRegistrationPaths = ['/fixture/one']
      page.registryMutationCompleted('register', {
        paths: ['/fixture/one']
      }, entry.projectController.state)
      t.step(60, function () {
        t.check(!page.setupActive && surface.section === 'overview', 'quick registration keeps direct Overview destination')
        t.check(requests.slice(3).every(function (r) {
          return r.action !== 'profile-save'
        }), 'registration completion saves no presets from the UI')
        t.done()
      })
    })
  })
}
