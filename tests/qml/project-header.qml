// Header Open choices: saved roles summary, immediate default toggles, last-role guard, one-off starts.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as ProjectUi

ShellRoot {
  id: host
  // Exact one-off requests emitted by the real header.
  property var oneOffs: []
  // Immediate default-role requests emitted by the real header.
  property var defaults: []
  QmlTest {
    id: t
  }
  ProjectUi.ProjectHeader {
    id: header
    width: 600
    openAvailable: true
    project: ({
        id: 'p-one',
        name: 'Repo',
        lastCheckoutId: 'c-main',
        openRoles: ['editor', 'agent'],
        tools: {
          editorId: 'code',
          terminalId: 'kitty',
          agentId: 'claude'
        },
        checkouts: [
          {
            id: 'c-main',
            path: '/repo',
            branch: 'main'
          }
        ]
      })
    tools: ({
        defaults: {},
        editors: [
          {
            id: "code",
            available: true,
            supported: true
          }
        ],
        terminals: [
          {
            id: "kitty",
            available: true,
            supported: true
          }
        ]
      })
    toolLabels: ({
        editor: 'VS Code',
        terminal: 'Kitty'
      })
    agentChoice: ({
        suggestedId: 'codex',
        options: [
          {
            id: 'claude',
            label: 'Claude Code',
            available: true,
            reason: '92% of Session (5-hour) · resets 14:20 · last used here'
          },
          {
            id: 'codex',
            label: 'Codex',
            available: true,
            reason: '10% used'
          }
        ]
      })
    onOneOffRequested: function (payload) {
      host.oneOffs.push(payload)
    }
    onDefaultRolesRequested: function (roles) {
      host.defaults.push(roles)
    }
  }
  Component.onCompleted: t.step(50, function () {
    t.equal(header.opensText, 'Opens Editor + Agent (Codex)', 'summary names saved roles and suggested provider')
    var rows = header.menuEntries()
    t.equal(rows.map(function (r) {
      return r.key || r.kind
    }), ['header', 'role:editor', 'role:terminal', 'role:agent', 'separator', 'header', 'start:codex', 'start:claude', 'only:terminal', 'only:editor'], 'menu lists defaults then one-off starts, suggested first')
    t.equal(rows[6].label, 'Start Codex', 'suggested start label')
    t.equal(rows[6].detail, 'Suggested · 10% used', 'suggested start explains why')
    header.choose('role:terminal')
    t.equal(host.defaults[0], ['editor', 'terminal', 'agent'], 'toggling saves canonical roles immediately')
    header.choose('start:claude')
    t.equal(host.oneOffs[0], {
      projectId: 'p-one',
      checkoutId: 'c-main',
      roles: ['agent'],
      newWindowRole: 'agent',
      agentId: 'claude'
    }, 'other provider is one click away')
    header.choose('only:terminal')
    t.equal(host.oneOffs[1], {
      projectId: 'p-one',
      checkoutId: 'c-main',
      roles: ['terminal']
    }, 'terminal only is a one-off role set')
    header.project = Object.assign({}, header.project, {
      openRoles: ['editor']
    })
    var editorRow = header.menuEntries()[1]
    t.check(editorRow.enabled === false && editorRow.tooltip === 'Open needs at least one tool', 'last role cannot be unticked')
    header.choose('role:editor')
    t.equal(host.defaults.length, 1, 'last-role toggle is ignored')
    header.agentChoice = {
      suggestedId: null,
      options: [
        {
          id: 'claude',
          label: 'Claude Code',
          available: false,
          reason: 'Usage unknown'
        },
        {
          id: 'codex',
          label: 'Codex',
          available: false,
          reason: 'Usage unknown'
        }
      ]
    }
    var agentRow = header.menuEntries()[3]
    t.check(agentRow.enabled === false && agentRow.detail === 'Install Claude Code or Codex to start agents here.', 'agent role disabled without CLIs')
    t.check(header.menuEntries().every(function (r) {
      return (r.key || '').indexOf('start:') !== 0
    }), 'no start rows without CLIs')
    header.tools = {
      defaults: {},
      editors: [],
      terminals: []
    }
    t.check(header.menuEntries()[1].enabled === false && header.menuEntries()[2].enabled === false, 'missing adapters disable default roles')
    var before = host.oneOffs.length
    header.choose('only:terminal')
    header.choose('only:editor')
    header.choose('start:untrusted')
    t.equal(host.oneOffs.length, before, 'disabled and unknown one-offs refuse dispatch')
    header.agentChoice = {
      suggestedId: 'codex',
      options: [
        {
          id: 'codex',
          label: 'Codex',
          available: true,
          reason: '10% used'
        }
      ]
    }
    t.equal(header.menuEntries()[3].detail, 'Agents run in a terminal. Choose one in Preferences.', 'agents require a supported host terminal')
    header.choose('start:codex')
    t.equal(host.oneOffs.length, before, 'agent one-off refuses unavailable terminal')
    header.tools = {
      defaults: {
        terminalId: 'kitty'
      },
      editors: [],
      terminals: [
        {
          id: 'kitty',
          available: true,
          supported: true
        }
      ]
    }
    header.pending = true
    header.choose('role:terminal')
    header.choose('start:codex')
    t.equal(host.defaults.length, 1, 'pending configure blocks another role toggle')
    t.equal(host.oneOffs.length, before, 'pending operation blocks one-offs')
    header.pending = false
    t.equal(header.menuEntries()[3].detail, 'Codex · Suggested · 10% used', 'agent checkbox includes provider and suggestion reason')
    header.project = Object.assign({}, header.project, {
      openRoles: undefined
    })
    t.equal(header.openRoles, ['editor', 'terminal'], 'legacy registrations retain their default roles')
    t.done()
  })
}
