// Real collector wire data flows through the client and expanded production view.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "plugins/araneadev.projects" as Projects
import "plugins/araneadev.projects/ProjectOverview.js" as Overview

ShellRoot {
  id: host
  // Exact temporary registration and unmodified collector response.
  property var fixture: null
  QmlTest {
    id: t
  }
  Projects.ProjectGitClient {
    id: client
    runner: function (argv, done) {
      t.equal(argv.slice(1), ['--project', host.fixture.project.id, '--checkout', host.fixture.project.lastCheckoutId, '--json'], 'collector request preserves exact registration identities')
      done(0, JSON.stringify(host.fixture.response), '')
    }
  }
  FloatingWindow {
    visible: true
    width: 900
    height: 900
    Projects.ProjectOverview {
      id: view
      width: parent.width
      model: Overview.overview(host.fixture ? host.fixture.project : null, client.checkoutId, client.current, {}, {}, {}, Date.now())
      displayOnly: true
    }
  }
  // Test-only walk retains real delegates and their consumer-visible labels.
  function descendants(item) {
    var children = t.childrenOf(item), result = []
    children.forEach(function (child) {
      result.push(child)
      result = result.concat(descendants(child))
    })
    return result
  }
  Process {
    command: ['bash', Qt.resolvedUrl('fixtures/project-git-view-fixture.sh').toString().replace('file://', '')]
    running: true
    stdout: StdioCollector {
      id: wire
    }
    stderr: StdioCollector {
      id: diagnostics
    }
    onExited: function (code) {
      t.equal(code, 0, 'real private collector fixture succeeds: ' + diagnostics.text)
      if (code !== 0) {
        t.done()
        return
      }
      host.fixture = JSON.parse(wire.text)
      client.projectId = host.fixture.project.id
      client.checkoutId = host.fixture.project.lastCheckoutId
      client.active = true
      t.step(80, function () {
        t.equal(client.current, host.fixture.response.data, 'client retains actual collector contract without fixture booleans')
        var section = descendants(view).filter(function (item) {
          return item.expanded !== undefined && item.git !== undefined
        })[0]
        section.expanded = true
        t.step(40, function () {
          var groups = descendants(section).filter(function (item) {
            return item.files !== undefined && item.modelData && item.modelData.key
          })
          var expected = {
            conflict: ['conflict.txt'],
            staged: ['conflict.txt', 'mixed.txt'],
            unstaged: ['conflict.txt', 'mixed.txt'],
            untracked: ['untracked \t\n <>&" $(touch NEVER)']
          }
          t.equal(groups.length, 4, 'expanded production view retains four state groups')
          groups.forEach(function (group) {
            t.equal(group.files.map(function (file) {
              return file.path
            }).sort(), expected[group.modelData.key].slice().sort(), 'actual collector paths appear in ' + group.modelData.key)
            var labels = descendants(group).filter(function (item) {
              return item.technical === true && item.text !== undefined
            })
            t.equal(labels.map(function (label) {
              return label.text
            }).sort(), expected[group.modelData.key].map(function (path) {
              return JSON.stringify(path)
            }).sort(), 'production path labels escape literal controls in ' + group.modelData.key)
            t.check(group.visible && labels.every(function (label) {
              return label.visible
            }), 'expanded paths are visible in ' + group.modelData.key)
            t.check(labels.every(function (label) {
              return label.textFormat === Text.PlainText
            }), 'path labels are plain text in ' + group.modelData.key)
          })
          var comparison = descendants(section).filter(function (item) {
            return item.text !== undefined && item.text.indexOf('Local refs; no remote fetch') >= 0
          })[0]
          t.check(!!comparison && /comparison not available/i.test(comparison.text) && comparison.text.indexOf('local-base') >= 0 && comparison.text.indexOf('null') < 0, 'unresolved real local upstream explains unavailable comparison without null values')
          view.model = {
            git: Object.assign({}, client.current, {
              ahead: 0,
              behind: 2
            }),
            services: [],
            checks: [],
            agents: [],
            workspaces: []
          }
          t.check(comparison.text.indexOf('0 ahead') >= 0 && comparison.text.indexOf('2 behind') >= 0, 'resolved zero divergence remains readable')
          view.model = {
            git: Object.assign({}, client.current, {
              upstream: null
            }),
            services: [],
            checks: [],
            agents: [],
            workspaces: []
          }
          t.check(/no upstream/i.test(comparison.text), 'absent upstream remains distinct from unresolved comparison')
          t.done()
        })
      })
    }
  }
}
