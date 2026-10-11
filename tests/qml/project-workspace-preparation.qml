// The shared project owner prepares workspaces without launching or requiring tools.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: root
  // Isolated registry protects actual repositories and settings.
  property var registry: ({
      schemaVersion: 1,
      revision: 0,
      roots: [],
      ignored: [],
      projects: [
        {
          id: 'p',
          name: 'Fixture',
          commonDir: '/repo/.git',
          lastCheckoutId: 'c',
          workspaceMode: 'dedicated',
          tools: {
            editorId: null,
            terminalId: null
          },
          checkouts: [
            {
              id: 'c',
              path: '/repo',
              primary: true
            }
          ],
          associations: []
        }
      ]
    })
  // Count generic project applications; preparation must keep this zero.
  property int launches: 0
  // Workspace preparation must not require an editor or terminal probe.
  property int probes: 0
  // Probe totals at preparation completion keep queued Open observations separate.
  property var preparationProbes: []
  // Observed workspace IDs expose occupied allocation behavior.
  property var focused: []
  QmlTest {
    id: t
  }
  Projects.ProjectsController {
    id: owner
    onOperationChanged: function (operation) {
      if (operation.workspaceOnly && operation.state === 'completed')
        root.preparationProbes.push(root.probes)
    }
    runtime: ({
        sessionId: 'desktop',
        snapshot: function () {
          return {
            available: true,
            currentWorkspaceId: 1,
            workspaces: [
              {
                id: 1,
                windows: 1
              }
            ],
            windows: []
          }
        },
        validateBindings: function (bindings, done) {
          Qt.callLater(function () {
            done({
              bindings: [],
              missing: []
            })
          })
        },
        focusWorkspace: function (id, done) {
          root.focused.push(id)
          done({
            ok: true,
            status: 'observed'
          })
        },
        launch: function (spec, done) {
          root.launches++
          done({
            ok: false
          })
        }
      })
    storeRunner: function (argv, done, input) {
      Qt.callLater(function () {
        if (input) {
          var req = JSON.parse(input), next = JSON.parse(JSON.stringify(root.registry))
          if (req.action === 'associate')
            next.projects[0].associations = [req.args]
          next.revision++
          root.registry = next
        }
        done({
          ok: true,
          state: root.registry
        })
      })
    }
    metadataRunner: function (argv, done) {
      done({
        ok: true,
        metadata: {
          path: '/repo',
          commonDir: '/repo/.git'
        }
      })
    }
    toolsRunner: function (argv, done) {
      root.probes++
      done({
        editors: [],
        terminals: [],
        defaults: {}
      })
    }
  }
  Component.onCompleted: {
    owner.refresh()
    t.waitFor(function () {
      return owner.registryReady && !owner.refreshing
    }, 1000, 'registry and startup probe ready', function () {
      var initialProbes = probes
      var prep = owner.prepareWorkspaceRequest({
        projectId: 'p',
        checkoutId: 'c'
      })
      var normal = owner.request({
        projectId: 'p',
        checkoutId: 'c'
      })
      t.check(prep.operationId !== normal.operationId, 'preparation first does not swallow normal open')
      t.waitFor(function () {
        return owner.operation(normal.operationId).state === 'completed'
      }, 1000, 'normal open completed', function () {
        t.equal(owner.operation(prep.operationId).outcome, 'observed', 'preparation requires no editor or terminal selection')
        t.equal(owner.operation(normal.operationId).error.code, 'TOOL_CHOICE_REQUIRED', 'ordinary open still requires tools')
        t.equal(launches, 0, 'preparation launches no application')
        t.equal(preparationProbes[0], initialProbes, 'preparation adds no tool probe after startup')
        t.equal(probes - initialProbes, 1, 'ordinary Open adds exactly one tool probe')
        t.equal(focused, [2], 'occupied workspace preserved by shared allocator')
        var n = owner.request({
          projectId: 'p',
          checkoutId: 'c'
        })
        var p = owner.prepareWorkspaceRequest({
          projectId: 'p',
          checkoutId: 'c'
        })
        t.check(n.operationId !== p.operationId, 'normal first does not swallow preparation')
        t.waitFor(function () {
          return owner.operation(p.operationId).state === 'completed'
        }, 1000, 'second preparation completes', function () {
          t.equal(owner.operation(p.operationId).outcome, 'observed', 'preparation observes existing association')
          t.equal(preparationProbes[1], initialProbes + 2, 'queued preparation adds no probe after the second ordinary Open')
          t.equal(owner.request({
            projectId: 'p',
            checkoutId: 'c',
            workspaceOnly: true
          }).error.code, 'INVALID_REQUEST', 'ordinary IPC cannot alter open behavior')
          t.done()
        })
      })
    })
  }
}
