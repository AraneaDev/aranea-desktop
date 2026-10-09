// Customization edits presentation drafts; Apply and Open have separate contracts.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: host
  // Typed configuration and owner requests collected through the real view.
  property var configurations: []
  // Accepted view requests collected without invoking the workspace owner.
  property var opens: []
  QmlTest {
    id: t
  }
  Settings.ProjectDetails {
    id: details
    width: 400
    project: ({
        id: 'p-one',
        name: 'Repo',
        lastCheckoutId: 'c-main',
        workspaceMode: 'dedicated',
        tools: {
          editorId: 'code',
          terminalId: 'kitty'
        },
        checkouts: [
          {
            id: 'c-main',
            path: '/repo',
            branch: 'main',
            primary: true
          },
          {
            id: 'c-other',
            path: '/outside',
            branch: 'other',
            primary: false
          }
        ]
      })
    tools: ({
        defaults: {
          editorId: 'code',
          terminalId: 'kitty'
        },
        editors: [
          {
            id: 'code',
            label: 'Code',
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
    onConfigureRequested: function (id, draft) {
      host.configurations.push([id, draft])
    }
    onOpenRequested: function (payload) {
      host.opens.push(payload)
    }
  }
  Component.onCompleted: t.step(50, function () {
    details.setDraft('name', 'Changed')
    details.setDraft('workspaceMode', 'current')
    t.equal(configurations.length, 0, 'editing does not persist')
    details.openProject()
    t.equal(opens[0], {
      projectId: 'p-one'
    }, 'ordinary Open uses saved owner preferences')
    details.applyDraft()
    t.equal(configurations[0], ['p-one',
      {
        name: 'Changed',
        editorId: 'code',
        terminalId: 'kitty',
        workspaceMode: 'current'
      }
    ], 'Apply persists exact draft configuration')
    details.discardDraft()
    t.equal(details.draft.name, 'Repo', 'Discard restores observed values')
    details.operation = {
      projectId: 'p-one',
      checkoutId: 'c-main',
      state: 'completed',
      steps: [
        {
          role: 'editor',
          status: 'failed'
        },
        {
          role: 'terminal',
          status: 'unconfirmed'
        }
      ]
    }
    details.recover('editor', 'retry')
    details.recover('terminal', 'new')
    t.equal(opens.slice(1), [
      {
        projectId: 'p-one',
        checkoutId: 'c-main',
        retryRole: 'editor'
      },
      {
        projectId: 'p-one',
        checkoutId: 'c-main',
        newWindowRole: 'terminal'
      }
    ], 'only explicit role recovery is sent')
    details.recover('editor', 'new')
    t.equal(opens.length, 3, 'unsupported recovery cannot silently duplicate a role')
    details.operation = {
      projectId: 'p-other',
      checkoutId: 'c-main',
      state: 'completed',
      steps: [
        {
          role: 'terminal',
          status: 'unconfirmed'
        }
      ]
    }
    t.check(!details.recoveryAllowed('terminal', 'new'), 'another project outcome cannot authorize role recovery')
    details.operation = {
      projectId: 'p-one',
      checkoutId: 'c-main',
      state: 'completed',
      steps: [
        {
          role: 'editor',
          status: 'failed'
        },
        {
          role: 'editor',
          status: 'observed'
        }
      ]
    }
    t.check(!details.recoveryAllowed('editor', 'retry'), 'latest role outcome controls retry affordance')
    details.operation = {
      projectId: 'p-one',
      checkoutId: 'c-main',
      state: 'completed',
      steps: [],
      error: {
        message: 'Folder missing.',
        recovery: 'Locate folder and retry.'
      }
    }
    var operationError = t.findChild(details, 'projectOperationError')
    t.check(!!operationError && operationError.text === 'Folder missing. Locate folder and retry.', 'owner failure exposes actionable recovery message')
    details.project = Object.assign({}, details.project, {
      tools: {
        editorId: null,
        terminalId: null
      }
    })
    t.check(!details.toolChoiceRequired, 'supported installed defaults avoid unnecessary tool chooser')
    t.equal([details.draft.editorId, details.draft.terminalId], ['code', 'kitty'], 'missing saved tools draft supported desktop defaults')
    details.tools = {
      defaults: {},
      editors: [],
      terminals: []
    }
    t.check(details.toolChoiceRequired, 'missing supported installed tools require choice')
    details.displayOnly = true
    details.openProject()
    details.applyDraft()
    t.equal(opens.length, 3, 'capture cannot submit Open')
    t.equal(configurations.length, 1, 'capture cannot configure')
    var fields = []
    function collectFields(item) {
      if (item.placeholderText !== undefined && item.background)
        fields.push(item)
      var kids = item.children || []
      for (var i = 0; i < kids.length; i++)
        collectFields(kids[i])
    }
    collectFields(details)
    t.check(fields.length >= 1, 'project details exposes editable fields')
    fields.forEach(function (field) {
      var fill = field.background.color
      t.check(!!fill && fill.a < 0.5, 'project fields retain readable dark surfaces during inert capture')
    })
    t.done()
  })
}
