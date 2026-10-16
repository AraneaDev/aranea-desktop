// Daily profile choices retain exact saved revisions and never mutate defaults.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Record real header requests without external effects.
  property var starts: []
  QmlTest {
    id: t
  }
  Projects.ProjectHeader {
    id: header
    width: 600
    openAvailable: true
    project: ({
        id: 'p',
        name: 'Repo',
        lastCheckoutId: 'c',
        lastProfileId: 'f-two',
        checkouts: [
          {
            id: 'c',
            path: '/repo',
            branch: 'main'
          }
        ],
        profiles: [
          {
            id: 'f-one',
            revision: 1,
            name: 'Editor',
            roles: ['editor'],
            tools: {
              editorId: 'code'
            }
          },
          {
            id: 'f-two',
            revision: 4,
            name: 'Terminal work',
            roles: ['terminal'],
            tools: {
              terminalId: 'kitty'
            }
          }
        ]
      })
    tools: ({
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
            id: 'kitty',
            label: 'Kitty',
            available: true,
            supported: true
          }
        ]
      })
  }
  Component.onCompleted: t.step(60, function () {
    t.check(typeof header.chooseProfile === 'function', 'header exposes explicit saved profile activation')
    if (typeof header.chooseProfile !== 'function') {
      t.done()
      return
    }
    header.startProfile.connect(function (id, revision) {
      host.starts.push([id, revision])
    })
    t.equal(header.profile.name, 'Terminal work', 'remembered profile is primary')
    t.equal(header.profileSummary, 'Kitty terminal', 'primary shows actual tools')
    t.findChild(header, 'projectPrimaryStart').clicked()
    t.equal(host.starts, [['f-two', 4]], 'Start uses remembered exact revision')
    var picker = t.findChild(header, 'profilePicker')
    t.equal(picker.showCheckoutContext, false, 'profile chooser hides irrelevant checkout branch context')
    t.equal(picker.searchPlaceholder, 'Search profiles…', 'chooser identifies its searchable profile context')
    picker.query = 'Editor'
    picker.select('f-one')
    t.equal(host.starts[1], ['f-one', 1], 'searchable chooser starts selected profile directly')
    header.pending = true
    header.chooseProfile('f-one')
    t.equal(host.starts.length, 2, 'pending submission refuses duplicate start')
    header.pending = false
    t.check(header.acceptanceUnknown !== undefined, 'header distinguishes unknown acceptance from preparation')
    if (header.acceptanceUnknown !== undefined) {
      header.acceptanceUnknown = true
      t.equal(t.findChild(header, 'projectPrimaryStart').text, 'Starting…', 'unknown acknowledgement is not ongoing preparation')
      header.acceptanceUnknown = false
    }
    header.displayOnly = true
    header.chooseProfile('f-one')
    t.equal(host.starts.length, 2, 'inert header refuses start')
    header.displayOnly = false
    header.project = Object.assign({}, header.project, {
      lastProfileId: null,
      profiles: []
    })
    t.equal(header.profile, null, 'missing profile never silently substitutes another')
    t.check(t.findChild(header, 'headerManageProfiles').visible, 'zero profile offers direct setup')
    t.equal(t.findChild(header, 'projectBranch'), null, 'branch appears only once in checkout control')
    t.done()
  })
}
