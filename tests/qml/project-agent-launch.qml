// Agent owner integration catches role defaults, unsafe dependencies and duplicate launches.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: root
  // External boundaries retain real owner sequencing while avoiding desktop launches.
  property var launched: []
  // Provider mutations record actual starts, never focus decisions.
  property var configures: []
  // Exact proven role focuses distinguish reuse from workspace focus.
  property var focused: []
  // Fresh independent runtime evidence for observed windows.
  property var proven: []
  // Changing the desktop identity invalidates ownership and probe callbacks.
  property string session: 'agent-session'
  // Held external responses can arrive after newer reads and transitions.
  property var deferredProbes: []
  // Pause probe completion to expose stale callback ordering.
  property bool holdProbes: false
  // Snapshot signal count catches usage and availability publication gaps.
  property int publications: 0
  // Sequential cases keep independent mutations and observations settled.
  property var tasks: []
  // Reject the provider mutation while other roles remain pending.
  property bool configureFailure: false
  // Delay editor observation past the agent provider write failure.
  property bool holdEditor: false
  // Accepted agent submissions retain uncertainty until reobserved.
  property bool unconfirmedAgent: false
  // Independent delayed editor result retained by the fake runtime.
  property var editorObservation: null
  // Count terminal publications per operation to catch duplicate completions.
  property var completions: ({})
  // Real composition is created after startup usage fixtures exist.
  property var composition: null
  // Watch file changes must publish a new consumer snapshot.
  property int usagePublications: 0
  // Fixture file writes advance only once the writer process exits.
  property var writeDone: null
  // The sandbox uses an isolated XDG state directory for watcher fixtures.
  readonly property string usageDirectory: Quickshell.env('XDG_STATE_HOME') + '/omarchy/agents/usage'
  // Mutable registry responses preserve real revision-sensitive owner writes.
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
          openRoles: ['editor', 'agent'],
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
            }
          ],
          associations: []
        }
      ]
    })
  // Canonical installed adapter and provider rows from the read-only helper.
  property var toolProbe: ({
      defaults: {
        editorId: 'code',
        terminalId: 'kitty'
      },
      editors: [
        {
          id: 'code',
          available: true,
          supported: true
        }
      ],
      terminals: [
        {
          id: 'kitty',
          available: true,
          supported: true
        }
      ],
      agents: [
        {
          id: 'claude',
          available: true,
          supported: true
        },
        {
          id: 'codex',
          available: true,
          supported: true
        }
      ]
    })
  QmlTest {
    id: t
  }
  Projects.ProjectsController {
    id: owner
    onSnapshotChanged: root.publications++
    onOperationChanged: function (op) {
      if (op.state === 'completed')
        root.completions[op.id] = (root.completions[op.id] || 0) + 1
    }
    runtime: ({
        sessionId: root.session,
        snapshot: function () {
          return {
            available: true,
            observedAt: Date.now(),
            currentWorkspaceId: 1,
            workspaces: [],
            windows: root.proven.map(function (binding) {
              return {
                address: binding.address,
                pid: binding.pid,
                appId: binding.appId,
                workspaceId: binding.workspaceId
              }
            })
          }
        },
        validateBindings: function (bindings, done) {
          Qt.callLater(function () {
            done({
              bindings: root.proven,
              missing: []
            })
          })
        },
        focusWorkspace: function (id, done) {
          Qt.callLater(function () {
            done({
              ok: true,
              status: 'observed'
            })
          })
        },
        focusBinding: function (binding, done) {
          root.focused.push(binding.role)
          Qt.callLater(function () {
            done({
              ok: true,
              status: 'observed',
              binding: binding
            })
          })
        },
        launch: function (spec, done) {
          root.launched.push(spec)
          if (spec.role === 'agent') {
            t.equal(root.registry.projects[0].tools.agentId, (spec.argv[spec.argv.length - 1] === 'claude' ? 'claude' : 'codex'), 'provider history is written at launch start')
            t.check(owner.queueActive, 'provider recording and launch stay inside submission transaction')
          }
          Qt.callLater(function () {
            done({
              ok: true,
              status: 'accepted',
              identity: {
                pid: 300 + root.launched.length,
                startTime: '1'
              }
            })
          })
        },
        observe: function (spec, baseline, done) {
          if (root.unconfirmedAgent && spec.role === 'agent') {
            Qt.callLater(function () {
              done({
                status: 'unconfirmed',
                code: 'OBSERVATION_TIMEOUT'
              })
            })
            return
          }
          var pid = 300 + root.launched.length
          var binding = {
            projectId: spec.projectId,
            checkoutId: spec.checkoutId,
            role: spec.role,
            sessionId: spec.sessionId,
            workspaceId: spec.workspaceId,
            address: '0x' + pid.toString(16),
            pid: pid,
            appId: spec.expectedAppId,
            evidence: {
              mode: spec.evidenceMode,
              processVerified: true,
              verifiedAt: Date.now(),
              startTime: '1'
            }
          }
          root.proven.push(binding)
          if (root.holdEditor && spec.role === 'editor')
            root.editorObservation = function () {
              done({
                status: 'observed',
                binding: binding
              })
            }
          else
            Qt.callLater(function () {
              done({
                status: 'observed',
                binding: binding
              })
            })
        }
      })
    storeRunner: function (argv, done, input) {
      Qt.callLater(function () {
        if (argv[1] === 'mutate') {
          var request = JSON.parse(input), next = JSON.parse(JSON.stringify(root.registry))
          t.equal(request.expectedRevision, next.revision, 'registry mutation uses current revision')
          if (request.action === 'configure' && root.configureFailure) {
            done({
              ok: false,
              error: {
                code: 'REGISTRY_WRITE_FAILED',
                message: 'fixture configure failure'
              }
            })
            return
          }
          next.revision++
          if (request.action === 'configure') {
            root.configures.push(request.args)
            next.projects[0].tools.agentId = request.args.agentId
          }
          if (request.action === 'associate')
            next.projects[0].associations = [
              {
                checkoutId: request.args.checkoutId,
                mode: request.args.mode,
                workspaceId: request.args.workspaceId,
                separate: request.args.separate
              }
            ]
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
      Qt.callLater(function () {
        done({
          ok: true,
          metadata: {
            path: argv[2],
            commonDir: '/fixture/.git'
          },
          error: null
        })
      })
    }
    toolsRunner: function (argv, done) {
      if (root.holdProbes) {
        root.deferredProbes.push(done)
        return
      }
      Qt.callLater(function () {
        done(root.toolProbe)
      })
    }
  }
  // Display captures still compose the real read-only usage watchers.
  Component {
    id: compositionFactory
    Projects.Projects {
      captureActive: true
      windowEnabled: false
    }
  }
  // File writes stay in the test sandbox; the production watchers perform real reads.
  Process {
    id: usageWriter
    onExited: function (code, status) {
      t.equal(code, 0, 'sandbox usage fixture written')
      root.writeDone()
    }
  }
  // Seed or update the watched files without invoking a provider or usage updater.
  function writeUsage(phase, done) {
    root.writeDone = done
    usageWriter.command = ['python', '-c', 'import pathlib,sys,json; p=pathlib.Path(sys.argv[1]); p.mkdir(parents=True,exist_ok=True); phase=sys.argv[2]; (p/"claude.json").write_text(json.dumps({"limits":[{"percent":0.25}],"updatedAt":"fixture-time","secret":"discard"}) if phase=="seed" else "null"); (p/"codex.json").write_text(json.dumps({"limits":[{"percent":0.5 if phase=="seed" else 0.7}],"updatedAt":"fixture-time","secret":"discard"}))', root.usageDirectory, phase]
    usageWriter.running = true
  }
  // Every fixture submission names an exact checkout instead of consuming a selection lease.
  function open(payload, verify) {
    var result = owner.request(Object.assign({
      projectId: 'p-fixture',
      checkoutId: 'c-main'
    }, payload))
    t.check(result.ok, 'request accepted')
    if (!result.ok) {
      t.done()
      return
    }
    t.waitFor(function () {
      return owner.operation(result.operationId).state === 'completed' && !owner.queueActive
    }, 3000, 'operation completes', function () {
      verify(owner.operation(result.operationId))
      next()
    })
  }
  // Advance scenarios only after previous observations and queue writes have settled.
  function next() {
    if (!tasks.length) {
      t.done()
      return
    }
    tasks.shift()()
  }
  // A fresh session removes prior ownership for independent launch scenarios.
  function reset() {
    root.session += '-next'
    root.proven = []
    root.launched = []
    root.configures = []
    root.focused = []
    owner.syncSession()
  }
  Component.onCompleted: {
    var valid = owner.validPayload({
      projectId: 'p-fixture',
      roles: ['agent'],
      newWindowRole: 'agent',
      agentId: 'codex'
    })
    t.check(valid, 'agent one-off payload is valid')
    if (!valid) {
      t.done()
      return
    }
    [
      {
        roles: []
      },
      {
        roles: ['agent', 'agent']
      },
      {
        roles: ['shell']
      },
      {
        roles: 'agent'
      },
      {
        agentId: 'gemini'
      },
      {
        agentId: null
      },
      {
        newWindowRole: 'shell'
      },
      {
        newWindowRole: 'agent',
        retryRole: 'agent'
      }
    ].forEach(function (payload) {
      t.check(!owner.validPayload(Object.assign({
        projectId: 'p-fixture'
      }, payload)), 'invalid role/provider payload rejected ' + JSON.stringify(payload))
    })
    t.check(owner.validPayload({
      projectId: 'p-fixture',
      retryRole: 'agent'
    }), 'agent retry supported')
    t.check(owner.validPayload({
      projectId: 'p-fixture',
      reobserveRole: 'agent'
    }), 'agent reobserve supported')
    owner.agentUsage = {
      claude: {
        limits: [
          {
            percent: 0.95,
            resetsAt: new Date(Date.now() + 3600000).toISOString()
          }
        ]
      },
      codex: {
        limits: [
          {
            percent: 0.1,
            resetsAt: new Date(Date.now() + 86400000).toISOString()
          }
        ]
      }
    }
    owner.refresh()
    t.waitFor(function () {
      return owner.registryReady && !owner.refreshing && owner.snapshot().agents.tools.length === 2
    }, 2000, 'startup probe published without opening a project', function () {
      tasks = [function () {
          t.equal(owner.snapshot().agents.usage.codex.limits[0].percent, 0.1, 'snapshot publishes usage')
          var before = root.publications
          owner.agentUsage = {
            claude: null,
            codex: null
          }
          t.check(root.publications > before, 'usage changes notify snapshot consumers')
          owner.agentUsage = {
            claude: {
              limits: [
                {
                  percent: 0.95
                }
              ]
            },
            codex: {
              limits: [
                {
                  percent: 0.1
                }
              ]
            }
          }
          open({}, function (op) {
            t.equal(root.launched.map(function (spec) {
              return spec.role
            }), ['editor', 'agent'], 'ordinary Open uses saved roles')
            t.equal(root.launched[1].argv.slice(-3), ['codex', '--cd', '/fixture'], 'usage suggestion chooses codex')
            t.equal(op.roles, ['editor', 'agent'], 'operation publishes resolved roles')
            t.equal(op.agentId, 'codex', 'operation retains suggested provider')
            t.equal(root.configures, [
              {
                projectId: 'p-fixture',
                agentId: 'codex'
              }
            ], 'launch records provider once')
          })
        }, function () {
          root.launched = []
          root.configures = []
          owner.agentUsage = {
            claude: {
              limits: [
                {
                  percent: 0.1
                }
              ]
            },
            codex: {
              limits: [
                {
                  percent: 0.95
                }
              ]
            }
          }
          var history = JSON.stringify(owner.roleHistory)
          open({}, function (op) {
            t.equal(root.launched.length, 0, 'ordinary Open focuses observed windows without duplicates')
            t.equal(root.focused, ['editor', 'agent'], 'real observed agent binding is focused')
            t.equal(root.registry.projects[0].tools.agentId, 'codex', 'focus-only Open preserves actual provider history despite changed suggestion')
            t.equal(root.configures.length, 0, 'focus does not record an unstarted provider')
            t.equal(JSON.stringify(owner.roleHistory), history, 'focusing existing windows preserves launch history')
          })
        }, function () {
          root.launched = []
          open({
            newWindowRole: 'agent',
            agentId: 'claude'
          }, function (op) {
            t.equal(root.launched.map(function (spec) {
              return spec.role
            }), ['agent'], 'implicit new-agent request launches agent alone')
            t.equal(root.launched[0].argv.slice(-1), ['claude'], 'explicit provider overrides suggestion')
            t.equal(op.agentId, 'claude', 'new session operation retains explicit provider')
          })
        }, function () {
          reset()
          delete root.registry.projects[0].openRoles
          open({}, function (op) {
            t.equal(root.launched.map(function (spec) {
              return spec.role
            }), ['editor', 'terminal'], 'legacy projects keep editor and terminal defaults')
          })
        }, function () {
          reset()
          owner.agentUsage = {}
          root.registry.projects[0].tools.agentId = 'claude'
          open({
            roles: ['agent']
          }, function (op) {
            t.equal(root.launched[0].argv.slice(-1), ['claude'], 'unknown usage falls back to installed last-used provider')
          })
        }, function () {
          reset()
          open({
            roles: ['agent'],
            agentId: 'codex'
          }, function (op) {
            t.equal(root.launched.map(function (spec) {
              return spec.role
            }), ['agent'], 'one-off roles do not inherit saved defaults')
          })
        }, function () {
          reset()
          root.unconfirmedAgent = true
          open({
            roles: ['agent'],
            agentId: 'codex'
          }, function (op) {
            t.equal(op.outcome, 'partial', 'accepted unconfirmed agent remains partial')
            t.check(op.steps.filter(function (step) {
              return step.role === 'agent'
            })[0].reobserveAvailable, 'accepted agent exposes safe reobservation')
          })
        }, function () {
          root.launched = []
          root.configures = []
          owner.agentUsage = {
            claude: {
              limits: [
                {
                  percent: 0.1
                }
              ]
            },
            codex: {
              limits: [
                {
                  percent: 0.95
                }
              ]
            }
          }
          open({
            roles: ['agent']
          }, function (op) {
            t.equal(root.launched.length, 0, 'uncertain agent ownership holds ordinary Open')
            t.equal(root.configures.length, 0, 'held agent does not rewrite provider history')
          })
        }, function () {
          root.unconfirmedAgent = false
          open({
            reobserveRole: 'agent'
          }, function (op) {
            t.equal(op.outcome, 'observed', 'reobserve confirms retained accepted agent identity')
            t.equal(op.roles, ['agent'], 'reobserve publishes only its target role')
            t.equal(op.agentId, 'codex', 'reobserve metadata retains actual started provider without suggestion')
            t.equal(root.launched.length, 0, 'agent reobserve never launches')
            t.equal(root.configures.length, 0, 'agent reobserve never records another start')
          })
        }, function () {
          reset()
          root.toolProbe.agents = []
          open({
            roles: ['agent']
          }, function (op) {
            t.equal(op.error.code, 'AGENT_MISSING', 'no installed provider is actionable failure')
            t.equal(root.launched.length, 0, 'missing provider never launches')
          })
        }, function () {
          root.toolProbe.agents = [
            {
              id: 'codex',
              available: true,
              supported: true
            }
          ]
          open({
            roles: ['agent'],
            agentId: 'claude'
          }, function (op) {
            t.equal(op.error.code, 'AGENT_MISSING', 'explicit uninstalled provider is not substituted')
          })
        }, function () {
          root.toolProbe.terminals = []
          open({
            roles: ['agent'],
            agentId: 'codex'
          }, function (op) {
            t.equal(op.error.code, 'TOOL_CHOICE_REQUIRED', 'agent host terminal must be installed')
            t.equal(op.error.message, 'Agents run in a terminal. Choose one in Preferences.', 'terminal recovery directs Preferences')
          })
        }, function () {
          reset()
          root.toolProbe.terminals = [
            {
              id: 'kitty',
              available: true,
              supported: true
            }
          ]
          root.registry.projects[0].openRoles = ['editor', 'agent']
          root.registry.projects[0].tools.agentId = 'claude'
          root.configureFailure = true
          root.holdEditor = true
          t.step(250, function () {
            t.check(!!root.editorObservation, 'editor observation remains independent during provider write failure')
            root.editorObservation()
            root.holdEditor = false
          })
          open({
            agentId: 'codex'
          }, function (op) {
            t.equal(root.launched.map(function (spec) {
              return spec.role
            }), ['editor'], 'failed provider recording prevents agent launch')
            t.equal(op.steps.filter(function (step) {
              return step.role === 'agent'
            })[0].code, 'REGISTRY_WRITE_FAILED', 'provider write failure belongs to agent role')
            t.equal(op.steps.filter(function (step) {
              return step.role === 'editor'
            })[0].status, 'observed', 'independent editor observation survives provider write failure')
            t.equal(op.outcome, 'partial', 'mixed role write failure retains partial result')
            t.equal(root.completions[op.id], 1, 'write failure completes operation exactly once')
            t.equal(root.registry.projects[0].tools.agentId, 'claude', 'failed write preserves prior provider history')
            root.configureFailure = false
          })
        }, function () {
          var before = root.publications
          root.holdProbes = true
          owner.probeAgents()
          var callback = root.deferredProbes.pop()
          callback({
            ok: false
          })
          t.equal(owner.snapshot().agents.tools, [], 'failed probe clears stale availability')
          t.check(root.publications > before, 'probe publication notifies snapshots')
          owner.probeAgents()
          callback = root.deferredProbes.pop()
          owner.captureActive = true
          owner.captureActive = false
          callback({
            agents: [
              {
                id: 'claude',
                available: true
              }
            ]
          })
          t.equal(owner.agentTools, [], 'capture round trip invalidates late probe callback')
          owner.probeAgents()
          callback = root.deferredProbes.pop()
          root.session += '-changed'
          callback({
            agents: [
              {
                id: 'claude',
                available: true
              }
            ]
          })
          t.equal(owner.agentTools, [], 'session transition invalidates late probe callback before publication')
          owner.probeAgents()
          var older = root.deferredProbes.pop()
          owner.probeAgents()
          var newer = root.deferredProbes.pop()
          newer({
            agents: [
              {
                id: 'codex',
                available: true
              }
            ]
          })
          older({
            agents: [
              {
                id: 'claude',
                available: true
              }
            ]
          })
          t.equal(owner.agentTools[0].id, 'codex', 'newest probe wins over late older response')
          owner.captureActive = true
          owner.probeAgents()
          t.equal(root.deferredProbes.length, 0, 'capture refuses probe boundary')
          next()
        }, function () {
          writeUsage('seed', function () {
            root.composition = compositionFactory.createObject(root)
            root.composition.owner.snapshotChanged.connect(function () {
              root.usagePublications++
            })
            t.equal(root.composition.usageDir, root.usageDirectory, 'watchers use shared Agents state directory')
            t.waitFor(function () {
              return root.composition.owner.agentUsage.claude && root.composition.owner.agentUsage.codex
            }, 2000, 'startup usage files loaded without opening presentation', function () {
              t.equal(root.composition.owner.snapshot().agents.usage, {
                claude: {
                  limits: [
                    {
                      percent: 0.25
                    }
                  ],
                  updatedAt: 'fixture-time'
                },
                codex: {
                  limits: [
                    {
                      percent: 0.5
                    }
                  ],
                  updatedAt: 'fixture-time'
                }
              }, 'startup watchers trim irrelevant fields and publish both providers')
              var before = root.usagePublications
              writeUsage('update', function () {
                t.waitFor(function () {
                  return root.composition.owner.agentUsage.claude === null && root.composition.owner.agentUsage.codex.limits[0].percent === 0.7
                }, 2000, 'usage file changes observed read-only', function () {
                  t.check(root.usagePublications > before, 'watched usage changes notify snapshot consumers')
                  t.equal(root.composition.owner.snapshot().agents.usage.claude, null, 'invalid usage file becomes unknown')
                  next()
                })
              })
            })
          })
        }]
      next()
    })
  }
}
