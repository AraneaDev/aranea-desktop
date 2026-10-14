// Production editor keeps saved revisions, dependencies and capture drafts inert.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Collect typed saves without launching or mutating a registry.
  property var saves: []
  QmlTest {
    id: t
  }
  Projects.ProjectProfileEditor {
    id: editor
    width: 360
    tools: ({
        defaults: {
          terminalId: 'kitty'
        },
        editors: [
          {
            id: 'code',
            label: 'VS Code',
            available: true,
            supported: true
          },
          {
            id: 'nvim',
            label: 'Neovim',
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
        ],
        agents: [
          {
            id: 'claude',
            label: 'Claude Code',
            available: true,
            supported: true
          },
          {
            id: 'codex',
            label: 'Codex',
            available: true,
            supported: true
          }
        ]
      })
    onSaveRequested: function (profile, revision) {
      host.saves.push([profile, revision])
    }
  }
  Component.onCompleted: t.step(50, function () {
    editor.begin({
      id: 'f-one',
      revision: 7,
      name: '<b>Work</b>',
      roles: ['editor'],
      tools: {
        editorId: 'code',
        terminalId: null,
        agentId: null
      }
    })
    t.check(!t.findChild(editor, 'profileAgentSettings').visible, 'provider controls hidden for editor-only profile')
    editor.setName('Renamed')
    editor.save()
    t.equal(saves[0], [
      {
        name: 'Renamed',
        roles: ['editor'],
        tools: {
          editorId: 'code',
          terminalId: null,
          agentId: null
        },
        id: 'f-one'
      },
      7], 'rename uses original exact revision and only profile fields')
    editor.setTool('editorId', 'nvim')
    t.equal(editor.draft.tools.terminalId, 'kitty', 'Neovim preselects available terminal')
    t.check(t.findChild(editor, 'profileTerminalHint').visible, 'Neovim dependency is explained inline')
    editor.toggleRole('agent')
    t.check(t.findChild(editor, 'profileAgentSettings').visible, 'agent provider controls become relevant')
    editor.setTool('agentId', 'codex')
    editor.save()
    t.equal(saves[1][0].tools.agentId, 'codex', 'both providers permit explicit alternative')
    editor.tools = {
      editors: [
        {
          id: 'code',
          available: true,
          supported: true
        }
      ],
      terminals: [],
      agents: []
    }
    editor.save()
    t.equal(saves.length, 2, 'unavailable saved adapters cannot silently switch')
    t.check(!!editor.fieldError, 'unavailable selection retains recovery feedback')
    editor.begin({
      name: 'Code',
      roles: ['editor'],
      tools: {
        editorId: 'code',
        terminalId: null,
        agentId: null
      }
    })
    editor.save()
    t.equal(saves[2][1], 0, 'new profiles have no existing revision guard')
    editor.setName(' ')
    editor.save()
    t.equal(saves.length, 3, 'blank name retains draft without submission')
    editor.displayOnly = true
    editor.setName('Unexpected')
    editor.toggleRole('terminal')
    editor.save()
    t.equal(editor.draft.name, ' ', 'capture refuses edits and save')
    t.equal(saves.length, 3, 'capture cannot persist')
    t.done()
  })
}
