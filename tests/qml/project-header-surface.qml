// Header role saves cross the real registry client; short-window menus escape clipping.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Held helper callbacks expose serialization and authoritative publication.
  property var calls: []
  // Real one-off owner transport requests intercepted at the IPC boundary.
  property var ipcCalls: []
  QmlTest {
    id: t
  }
  TestCase {
    id: input
    when: false
  }
  Projects.ProjectsPresentation {
    id: entry
    windowEnabled: false
  }
  FloatingWindow {
    visible: true
    implicitWidth: 420
    implicitHeight: 240
    Projects.ProjectsSurface {
      id: surface
      anchors.fill: parent
      root: entry
    }
  }
  Component.onCompleted: t.step(80, function () {
    entry.activityClient.captureActive = true
    entry.discoveryClient.captureActive = true
    entry.projectClient.captureActive = true
    entry.projectController.runner = function (argv, payload, done) {
      host.calls.push({
        argv: argv,
        payload: payload,
        done: done
      })
    }
    entry.projectController.state = {
      revision: 4,
      roots: [],
      ignored: [],
      projects: [
        {
          id: 'p-one',
          name: 'Repo',
          tools: {
            editorId: 'code',
            terminalId: 'kitty'
          },
          openRoles: ['editor', 'agent'],
          lastCheckoutId: 'c-main',
          checkouts: [
            {
              id: 'c-main',
              path: '/repo',
              branch: 'main'
            }
          ]
        }
      ]
    }
    entry.projectController.tools = {
      defaults: {},
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
    }
    entry.projectClient.snapshot = {
      availability: {
        compositor: true
      },
      bindings: [],
      operations: [],
      agents: {
        tools: [
          {
            id: 'codex',
            label: 'Codex',
            available: true
          }
        ],
        usage: {}
      }
    }
    entry.projectClient.available = true
    surface.navigate('p-one')
    t.step(80, function () {
      var header = t.findChild(surface, 'projectHeader')
      t.check(header.agentChoice === surface.agentChoice, 'surface supplies its shared suggestion to header')
      header.choose('role:terminal')
      t.equal(host.calls.length, 1, 'default toggle dispatches exactly one configure helper')
      t.equal(JSON.parse(host.calls[0].payload), {
        action: 'configure',
        args: {
          projectId: 'p-one',
          openRoles: ['editor', 'terminal', 'agent']
        },
        expectedRevision: 4
      }, 'autosave encodes canonical roles through real registry transport')
      t.check(entry.projectController.pending && header.pending, 'held configure disables header immediately')
      header.choose('role:editor')
      t.equal(host.calls.length, 1, 'rapid second toggle cannot overwrite pending selection')
      t.equal(header.openRoles, ['editor', 'agent'], 'pending save retains authoritative roles until readback')
      var saved = Object.assign({}, entry.projectController.state, {
        revision: 5,
        projects: [Object.assign({}, entry.projectController.state.projects[0], {
            openRoles: ['editor', 'terminal', 'agent']
          })]
      })
      host.calls[0].done(0, JSON.stringify({
        ok: true,
        state: saved
      }), '')
      t.equal(header.openRoles, ['editor', 'terminal', 'agent'], 'authoritative configure readback updates header checks')
      t.check(!header.pending && !t.findChild(surface, 'projectsPage').details.dirty, 'autosave unlocks controls without creating a preference draft')
      header.choose('role:editor')
      t.equal(JSON.parse(host.calls[1].payload).args.openRoles, ['terminal', 'agent'], 'next toggle derives from completed readback rather than stale roles')
      host.calls[1].done(1, JSON.stringify({
        ok: false,
        error: {
          message: 'Save refused'
        }
      }), '')
      t.equal(header.openRoles, ['editor', 'terminal', 'agent'], 'failed autosave preserves saved selection and unlocks retry')
      var split = t.findChild(surface, 'projectPrimaryOpen'), toggle = t.findChild(split, 'splitToggle')
      toggle.forceActiveFocus()
      input.keyClick(Qt.Key_Down)
      t.step(80, function () {
        var menu = t.findChild(surface, 'splitMenu')
        t.check(menu.opened && menu.activeFocus, 'actual surface dropdown opens with keyboard focus')
        t.check(menu.parent === surface && menu.z > 0, 'menu uses unclipped surface overlay above siblings')
        var p = menu.mapToItem(surface, 0, 0)
        t.check(p.x >= 0 && p.y >= 0 && p.x + menu.width <= surface.width && p.y + menu.height <= surface.height, 'short narrow menu fits actual host bounds')
        t.check(menu.height < menu.implicitHeight, 'tall menu becomes scrollable rather than overflowing window')
        input.keyClick(Qt.Key_End)
        for (var i = 0; i < 12; i++)
          input.keyClick(Qt.Key_Down)
        var rows = t.findChildren(menu, 'menuRow'), cursorRow = rows[menu.cursor], pos = cursorRow.mapToItem(menu, 0, 0)
        t.check(pos.y >= 0 && pos.y + cursorRow.height <= menu.height, 'keyboard navigation reveals lower menu rows in bounded popup')
        entry.projectClient.runner = function (argv, done) {
          host.ipcCalls.push(argv)
          done(0, JSON.stringify({
            ok: false,
            error: {
              code: 'FIXTURE',
              message: 'Inert request captured'
            }
          }), '')
        }
        entry.projectClient.captureActive = false
        input.mouseClick(cursorRow)
        t.equal(JSON.parse(host.ipcCalls[host.ipcCalls.length - 1].slice(-1)[0]), {
          projectId: 'p-one',
          checkoutId: 'c-main',
          roles: ['editor']
        }, 'overlay pointer row reaches real owner request route with one-off role only')
        t.check(!menu.opened, 'overlay action pointer closes the menu')
        toggle.forceActiveFocus()
        input.keyClick(Qt.Key_Down)
        input.keyClick(Qt.Key_Escape)
        t.check(!menu.opened && toggle.activeFocus, 'Esc restores focus to surface dropdown')
        input.keyClick(Qt.Key_Down)
        header.visible = false
        t.check(!menu.opened, 'hiding the header closes its reparented overlay menu')
        t.done()
      })
    })
  })
}
