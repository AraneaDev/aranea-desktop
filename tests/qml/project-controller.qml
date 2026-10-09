// Sole owner orchestration is exercised with isolated registry and desktop boundaries.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: root
  // Launch counters catch duplicate ordinary opens and targeted retry errors.
  property int launches: 0
  // Dispatch history catches queue interleaving and unsafe workspace allocation.
  property var focused: []
  // Fresh mutable registry returned through the real owner boundary.
  property var registry: ({
      schemaVersion: 1,
      revision: 0,
      roots: [],
      ignored: [],
      projects: [
        {
          id: 'p-fixture',
          name: 'Fixture',
          commonDir: '/fixture/.git',
          lastCheckoutId: 'c-main',
          workspaceMode: 'dedicated',
          tools: {
            editorId: 'code',
            terminalId: 'kitty'
          },
          checkouts: [
            {
              id: 'c-main',
              path: '/fixture',
              branch: 'main',
              primary: true
            },
            {
              id: 'c-other',
              path: '/other',
              branch: 'other',
              primary: false
            }
          ],
          associations: []
        }
      ]
    })
  // Window availability can change while a request is queued.
  property var workspaces: []
  // Held callbacks let the second request arrive before the first finishes.
  property var observations: []
  // Store calls are recorded to prove capture and rejection never mutate storage.
  property int storeCalls: 0
  // Observations retained by the fake desktop represent actual independent role results.
  property var windows: []
  // Test-only session identity changes reject late callbacks.
  property string session: 'fixture-session'
  // Fail only the selected role, independently of the other launch.
  property bool failTerminal: false
  // Exact window focuses are verified separately from workspace focus.
  property var bindingFocuses: []
  // Helper failures are injected below process execution, retaining real owner behavior.
  property string faultMode: ''
  // A user or client may occupy a freshly allocated workspace before launch.
  property bool raceOnce: false
  // Saved operation identifies the first result evicted by bounded retention.
  property string firstRetained: ''
  // Recursion counts completed requests without waiting for the desktop.
  property int retentionCount: 0
  // Exact observed bindings can close positively while uncertain roles remain held.
  property bool confirmedClosed: false
  // A partial closure proof cannot discard another uncertain owned copy.
  property string closureAddress: ''
  // Resume window evidence is supplied only through the independent runtime validator.
  property var proven: []
  QmlTest {
    id: t
  }
  Projects.ProjectsController {
    id: unavailable
    captureActive: true
  }
  Projects.ProjectsController {
    id: controller
    runtime: ({
        sessionId: root.session,
        snapshot: function () {
          return {
            available: true,
            observedAt: Date.now(),
            currentWorkspaceId: 8,
            workspaces: root.workspaces,
            windows: root.windows
          }
        },
        validateBindings: function (bindings, done) {
          done({
            bindings: root.proven,
            missing: root.confirmedClosed ? bindings.filter(function (binding) {
              return binding.role === 'editor' && (!root.closureAddress || binding.address === root.closureAddress)
            }).map(function (binding) {
              return {
                binding: binding,
                identity: {
                  pid: binding.pid,
                  startTime: binding.evidence.startTime,
                  address: binding.address
                }
              }
            }) : []
          })
        },
        focusBinding: function (binding, done) {
          root.bindingFocuses.push(binding.address)
          done({
            ok: true,
            status: 'observed',
            binding: binding
          })
        },
        focusWorkspace: function (id, done) {
          root.focused.push(id)
          if (root.raceOnce && id === 1) {
            root.raceOnce = false
            root.workspaces = [
              {
                id: 1,
                windows: 1
              }
            ]
            root.windows = [
              {
                address: '0xfaa',
                pid: 99,
                appId: 'unrelated',
                workspaceId: 1
              }
            ]
          }
          Qt.callLater(function () {
            done({
              ok: true,
              status: 'observed'
            })
          })
        },
        launch: function (spec, done) {
          root.launches++
          Qt.callLater(function () {
            done(root.failTerminal && spec.role === 'terminal' ? {
              ok: false,
              status: 'failed',
              code: 'TOOL_MISSING'
            } : {
              ok: true,
              status: 'accepted',
              identity: {
                pid: 22,
                startTime: '123'
              }
            })
          })
        },
        observe: function (spec, baseline, done) {
          root.observations.push({
            spec: spec,
            done: done
          })
        }
      })
    onOperationChanged: function (operation) {
      if (root.retentionCount && operation.state === 'completed') {
        if (root.retentionCount < 105) {
          root.retentionCount++
          Qt.callLater(function () {
            controller.request({
              projectId: 'p-fixture',
              checkoutId: 'c-main'
            })
          })
        } else {
          root.retentionCount = 0
          t.equal(controller.operations.filter(function (op) {
            return op.state === 'completed'
          }).length, 100, 'latest 100 completed operations retained')
          t.equal(controller.operation(root.firstRetained).error.code, 'OPERATION_NOT_FOUND', 'old completed operation evicted')
          t.equal(launches, 12, 'retention never erases uncertain role history into duplicate launches')
          t.equal(controller.bindings.filter(function (binding) {
            return binding.role === 'editor'
          }).map(function (binding) {
            return binding.address
          }).sort(), ['0xabc', '0xdef'], 'binding refresh retains each separate owned identity')
          verifyFailures(0)
        }
      }
    }
    storeRunner: function (argv, done, input) {
      root.storeCalls++
      if (root.faultMode === 'registry' || (root.faultMode === 'conflict' && argv[1] === 'mutate')) {
        done({
          ok: false,
          state: root.registry,
          error: {
            code: root.faultMode === 'registry' ? 'REGISTRY_INVALID' : 'REGISTRY_CONFLICT',
            message: 'fixture error',
            recovery: 'repair fixture'
          }
        })
        return
      }
      Qt.callLater(function () {
        if (argv[1] === 'mutate') {
          var request = JSON.parse(input)
          t.equal(request.expectedRevision, root.registry.revision, 'mutation uses freshest revision')
          var next = JSON.parse(JSON.stringify(root.registry))
          next.revision++
          if (request.action === 'associate') {
            t.equal(Object.keys(request.args).sort(), ['checkoutId', 'mode', 'projectId', 'separate', 'workspaceId'], 'association sends only declared store fields')
            var a = request.args
            next.projects[0].associations = next.projects[0].associations.filter(function (row) {
              return a.separate ? !row.separate || row.checkoutId !== a.checkoutId : row.separate
            }).concat([
              {
                checkoutId: a.checkoutId,
                mode: a.mode,
                workspaceId: a.workspaceId,
                separate: a.separate
              }
            ])
          }
          if (request.action === 'select-checkout')
            next.projects[0].lastCheckoutId = request.args.checkoutId
          root.registry = next
        }
        done({
          ok: true,
          state: root.registry,
          error: null
        })
      })
    }
    metadataRunner: function (argv, done) {
      done({
        ok: true,
        metadata: {
          path: root.faultMode === 'moved' ? '/moved' : argv[2],
          commonDir: '/fixture/.git'
        },
        error: null
      })
    }
    toolsRunner: function (argv, done) {
      if (root.faultMode === 'probe') {
        done({
          ok: false,
          error: {
            code: 'DEPENDENCY_MISSING',
            message: 'probe missing'
          }
        })
        return
      }
      done({
        defaults: {
          editorId: root.faultMode === 'choice' ? null : 'code',
          terminalId: root.faultMode === 'choice' ? null : 'kitty'
        },
        editors: [
          {
            id: 'code'
          }
        ],
        terminals: [
          {
            id: 'kitty'
          }
        ]
      })
    }
  }
  // Complete each role separately and keep dispatch acceptance distinct from observation.
  function settleUnconfirmed(): void {
    var pending = observations.slice()
    observations = []
    pending.forEach(function (entry) {
      entry.done({
        ok: false,
        status: 'unconfirmed',
        code: 'OBSERVATION_TIMEOUT'
      })
    })
  }
  // Stable helper errors settle the owner without launching or resetting saved data.
  function verifyFailures(index: int): void {
    var modes = ['registry', 'moved', 'probe', 'choice', 'conflict']
    var codes = ['REGISTRY_INVALID', 'CHECKOUT_INVALID', 'DEPENDENCY_MISSING', 'TOOL_CHOICE_REQUIRED', 'REGISTRY_CONFLICT']
    if (index >= modes.length) {
      faultMode = ''
      registry.projects[0].tools = {
        editorId: 'code',
        terminalId: 'kitty'
      }
      controller.roleTimeout = 80
      var timed = controller.request({
        projectId: 'p-fixture',
        checkoutId: 'c-main',
        newWindowRole: 'editor'
      })
      t.waitFor(function () {
        return controller.operation(timed.operationId).state === 'completed'
      }, 2000, 'owner deadline settles a never-completing observer', function () {
        t.equal(controller.operation(timed.operationId).outcome, 'partial', 'owner watchdog keeps accepted launch partial')
        var settled = controller.operation(timed.operationId)
        settleUnconfirmed()
        t.equal(controller.operation(timed.operationId), settled, 'late observer callback cannot rewrite completed outcome')
        t.done()
      })
      return
    }
    faultMode = modes[index]
    if (faultMode === 'choice')
      registry.projects[0].tools = {
        editorId: null,
        terminalId: null
      }
    else
      registry.projects[0].tools = {
        editorId: 'code',
        terminalId: 'kitty'
      }
    var before = launches
    var savedIds = registry.projects.map(function (project) {
      return project.id
    })
    var failed = controller.request({
      projectId: 'p-fixture',
      checkoutId: 'c-main'
    })
    t.waitFor(function () {
      return controller.operation(failed.operationId).state === 'completed'
    }, 2000, 'helper failure settles ' + faultMode, function () {
      t.equal(controller.operation(failed.operationId).error.code, codes[index], 'helper error code is preserved ' + faultMode)
      t.equal(launches, before, 'helper failure cannot launch ' + faultMode)
      t.equal(controller.registry.projects.map(function (project) {
        return project.id
      }), savedIds, 'helper failure retains registered projects ' + faultMode)
      verifyFailures(index + 1)
    })
  }
  // Global submission sequencing releases allocation while independent role observations remain pending.
  function verifyQueue(): void {
    registry.projects[0].associations = []
    workspaces = []
    focused = []
    raceOnce = true
    var first = controller.request({
      projectId: 'p-fixture',
      checkoutId: 'c-main'
    })
    var other = controller.request({
      projectId: 'p-fixture',
      checkoutId: 'c-other',
      separate: true
    })
    t.check(first.operationId !== other.operationId, 'different checkout requests keep separate operations')
    t.waitFor(function () {
      return observations.length === 4
    }, 2000, 'queued checkout submits while first observation is pending', function () {
      t.equal(focused, [1, 2, 3], 'allocation race rechecks and preserves occupied workspace')
      t.equal(windows[0].workspaceId, 1, 'allocation preserves unrelated occupant without moving it')
      t.equal(observations.map(function (entry) {
        return entry.spec.workspaceId
      }), [2, 2, 3, 3], 'both roles explicitly target each reserved workspace')
      t.equal(observations.map(function (entry) {
        return entry.spec.cwd
      }), ['/fixture', '/fixture', '/other', '/other'], 'separate checkout launches exact registered path')
      var firstRole = observations.shift()
      var binding = {
        projectId: 'p-fixture',
        checkoutId: 'c-main',
        role: 'editor',
        workspaceId: 2,
        address: '0xabc',
        appId: 'code',
        pid: 22,
        sessionId: session,
        launchIdentity: {
          pid: 22,
          startTime: '123',
          sessionId: session,
          token: 'dev.aranea.fixture'
        },
        evidence: {
          mode: 'process-only',
          processVerified: true,
          startTime: '123',
          verifiedAt: Date.now()
        }
      }
      firstRole.done({
        ok: true,
        status: 'observed',
        binding: binding
      })
      settleUnconfirmed()
      windows = [
        {
          address: '0xabc',
          appId: 'code',
          pid: 22,
          workspaceId: 2
        }
      ]
      proven = [binding]
      var resume = controller.request({
        projectId: 'p-fixture',
        checkoutId: 'c-main'
      })
      t.waitFor(function () {
        return controller.operation(resume.operationId).state === 'completed'
      }, 2000, 'proven editor resumes independently', function () {
        t.equal(bindingFocuses, ['0xabc'], 'resume focuses exact proven editor address')
        t.equal(launches, 8, 'proven resume and uncertain terminal never duplicate')
        t.equal(controller.snapshot().bindings[0].address, '0xabc', 'snapshot publishes only owner-proven identities')
        var alternate = controller.request({
          projectId: 'p-fixture',
          checkoutId: 'c-other'
        })
        t.waitFor(function () {
          return controller.operation(alternate.operationId).state === 'completed'
        }, 2000, 'alternate checkout protects identified existing editor', function () {
          t.equal(controller.operation(alternate.operationId).workspaceId, 4, 'occupied alternate checkout gets a distinct reserved workspace')
          t.equal(controller.bindings[0].workspaceId, 2, 'existing checkout window is never moved into alternate checkout')
          t.equal(launches, 8, 'uncertain alternate roles stay held instead of duplicating')
          windows = []
          proven = []
          confirmedClosed = true
          var closed = controller.request({
            projectId: 'p-fixture',
            checkoutId: 'c-main'
          })
          t.waitFor(function () {
            return observations.length === 1
          }, 2000, 'confirmed editor closure launches only missing role', function () {
            t.equal(observations[0].spec.role, 'editor', 'positive exact closure differs from uncertain terminal')
            t.equal(launches, 9, 'only positively closed observed role launches')
            settleUnconfirmed()
            confirmedClosed = false
            var explicit = controller.request({
              projectId: 'p-fixture',
              checkoutId: 'c-main',
              newWindowRole: 'editor'
            })
            t.waitFor(function () {
              return observations.length === 1
            }, 2000, 'explicit new window can duplicate uncertain role', function () {
              t.equal(launches, 10, 'explicit role overrides uncertain ownership')
              var copy = Object.assign({}, binding, {
                address: '0xdef',
                pid: 33,
                evidence: {
                  mode: 'process-only',
                  processVerified: true,
                  startTime: '456',
                  verifiedAt: Date.now()
                },
                launchIdentity: {
                  pid: 33,
                  startTime: '456',
                  sessionId: session,
                  token: 'dev.aranea.copy'
                }
              })
              observations.shift().done({
                ok: true,
                status: 'observed',
                binding: copy
              })
              proven = [copy]
              windows = [
                {
                  address: '0xdef',
                  pid: 33,
                  appId: 'code',
                  workspaceId: 2
                }
              ]
              t.equal(controller.bindings.filter(function (owned) {
                return owned.role === 'editor'
              }).map(function (owned) {
                return owned.address
              }).sort(), ['0xabc', '0xdef'], 'explicit new window retains older owned process evidence')
              proven = []
              windows = []
              confirmedClosed = true
              closureAddress = '0xabc'
              var uncertainCopy = controller.request({
                projectId: 'p-fixture',
                checkoutId: 'c-main'
              })
              t.waitFor(function () {
                return controller.operation(uncertainCopy.operationId).state === 'completed'
              }, 2000, 'remaining uncertain copy prevents confirmed-missing launch', function () {
                t.equal(launches, 10, 'every owned copy must close before automatic relaunch')
                confirmedClosed = false
                closureAddress = ''
                proven = [copy]
                windows = [
                  {
                    address: '0xdef',
                    pid: 33,
                    appId: 'code',
                    workspaceId: 2
                  }
                ]
                // Failed selected role retries; the other role remains held.
                failTerminal = true
                var failed = controller.request({
                  projectId: 'p-fixture',
                  checkoutId: 'c-main',
                  newWindowRole: 'terminal'
                })
                t.waitFor(function () {
                  return controller.operation(failed.operationId).state === 'completed'
                }, 2000, 'late terminal failure retained', function () {
                  t.equal(launches, 11, 'explicit failing terminal invoked once')
                  // Ordinary open may retry known failed roles; keep it unconfirmed before retention.
                  failTerminal = false
                  var retry = controller.request({
                    projectId: 'p-fixture',
                    checkoutId: 'c-main',
                    retryRole: 'terminal'
                  })
                  t.waitFor(function () {
                    return observations.length === 1
                  }, 2000, 'retention seed retry accepted', function () {
                    settleUnconfirmed()
                    firstRetained = first.operationId
                    retentionCount = 1
                    controller.request({
                      projectId: 'p-fixture',
                      checkoutId: 'c-main'
                    })
                  })
                })
              })
            })
          })
        })
      })
    })
  }
  Component.onCompleted: {
    unavailable.captureActive = false
    var refused = unavailable.request({
      projectId: 'p-fixture'
    })
    t.equal(refused.error && refused.error.code, 'DEPENDENCY_MISSING', 'missing runtime refuses before hanging accepted operation')
    unavailable.captureActive = true
    controller.captureActive = true
    t.equal(controller.request({
      projectId: 'p-fixture'
    }).error.code, 'INERT_MODE', 'capture refuses every request')
    controller.refresh()
    t.equal(storeCalls, 0, 'capture never reads registry or processes')
    controller.captureActive = false
    var first = controller.request({
      projectId: 'p-fixture',
      checkoutId: 'c-main'
    })
    var second = controller.request({
      projectId: 'p-fixture',
      checkoutId: 'c-main'
    })
    t.check(first.ok && second.ok, 'same checkout requests accepted')
    t.equal(second.operationId, first.operationId, 'pending operation coalesced before async registry read')
    t.waitFor(function () {
      return observations.length === 2
    }, 2000, 'both roles observe independently', function () {
      t.equal(launches, 2, 'one editor and one terminal launch')
      t.equal(focused, [1], 'global allocation chooses unused workspace')
      settleUnconfirmed()
      t.equal(controller.operation(first.operationId).outcome, 'partial', 'accepted unconfirmed is partial')
      var held = controller.request({
        projectId: 'p-fixture',
        checkoutId: 'c-main'
      })
      t.waitFor(function () {
        return controller.operation(held.operationId).state === 'completed'
      }, 2000, 'ordinary reopen holds uncertain roles', function () {
        t.equal(launches, 2, 'ordinary open never duplicates unconfirmed launch')
        failTerminal = true
        var fresh = controller.request({
          projectId: 'p-fixture',
          checkoutId: 'c-main',
          newWindowRole: 'terminal'
        })
        t.waitFor(function () {
          return controller.operation(fresh.operationId).state === 'completed'
        }, 2000, 'explicit terminal failure settles independently', function () {
          t.equal(launches, 3, 'explicit new window launches only selected uncertain role')
          failTerminal = false
          var retry = controller.request({
            projectId: 'p-fixture',
            checkoutId: 'c-main',
            retryRole: 'terminal'
          })
          t.waitFor(function () {
            return observations.length === 1
          }, 2000, 'failed role retries', function () {
            t.equal(observations[0].spec.role, 'terminal', 'retry observes selected role only')
            t.equal(launches, 4, 'retry does not relaunch editor')
            session = 'next-session'
            controller.snapshot()
            settleUnconfirmed()
            t.equal(controller.operation(retry.operationId).error.code, 'SESSION_CHANGED', 'session change invalidates pending work')
            t.equal(controller.snapshot().bindings, [], 'new session clears runtime bindings')
            t.equal(controller.request({
              projectId: 'p-fixture',
              retryRole: 'terminal',
              newWindowRole: 'editor'
            }).error.code, 'INVALID_REQUEST', 'contradictory action flags rejected')
            verifyQueue()
          })
        })
      })
    })
  }
}
