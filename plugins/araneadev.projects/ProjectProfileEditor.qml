// Focused profile draft: supported role choices, exact edit revision, no launch authority.
pragma ComponentBehavior: Bound
// Host typography tokens are runtime QObject properties.
// qmllint disable missing-property
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "../araneadev.shared" as Aranea
import "ProjectProfiles.js" as Profiles

ColumnLayout {
  id: editor
  // Probe observations never silently overwrite saved choices.
  property var tools: ({})
  // Capture blocks mutations and transport.
  property bool displayOnly: false
  // Shared registry serialization prevents duplicate submission.
  property bool pending: false
  // Pointer settling follows the parent surface.
  property var pointerGate: null
  // Only these fields belong to a profile; checkout selection belongs to the project.
  property var draft: ({
      name: '',
      roles: [],
      tools: {
        editorId: null,
        terminalId: null,
        agentId: null
      }
    })
  // Original edit revision never rebases on refresh.
  property int expectedProfileRevision: 0
  // Validation remains beside the retained draft.
  property string fieldError: ''
  // Terminal settings apply to explicit terminals and dependent tools.
  readonly property bool needsTerminal: draft.roles.indexOf('terminal') >= 0 || draft.roles.indexOf('agent') >= 0 || draft.roles.indexOf('editor') >= 0 && (draft.tools.editorId || Profiles.preferred(tools, 'editors', 'editorId')) === 'nvim'
  // Save is configuration only, never activation.
  signal saveRequested(var profile, int expectedProfileRevision)
  // Parent owns navigation and draft lifetime.
  signal cancelRequested
  // Copy the saved profile once, stripping every non-profile field.
  function begin(profile: var): void {
    var p = profile || {}
    draft = {
      name: p.name || '',
      roles: (p.roles || []).slice(),
      tools: Object.assign({
        editorId: null,
        terminalId: null,
        agentId: null
      }, p.tools || {})
    }
    if (p.id)
      draft.id = p.id
    expectedProfileRevision = p.revision || 0
    fieldError = ''
  }
  // Local name editing never affects the saved revision.
  function setName(value: string): void {
    if (displayOnly || pending)
      return
    draft = Object.assign({}, draft, {
      name: value
    })
    fieldError = ''
  }
  // Preselect dependencies only during explicit editing, never on observation refresh.
  function setTool(key: string, value: string): void {
    if (displayOnly || pending || ['editorId', 'terminalId', 'agentId'].indexOf(key) < 0)
      return
    var selected = Object.assign({}, draft.tools, {
      [key]: value
    })
    if (key === 'editorId' && value === 'nvim' && !selected.terminalId)
      selected.terminalId = Profiles.preferred(tools, 'terminals', 'terminalId')
    draft = Object.assign({}, draft, {
      tools: selected
    })
    fieldError = ''
  }
  // Role order matches the registry contract; unselected settings are cleared.
  function toggleRole(role: string): void {
    if (displayOnly || pending || ['editor', 'terminal', 'agent'].indexOf(role) < 0)
      return
    var roles = draft.roles.indexOf(role) >= 0 ? draft.roles.filter(function (r) {
      return r !== role
    }) : draft.roles.concat([role])
    roles = ['editor', 'terminal', 'agent'].filter(function (r) {
      return roles.indexOf(r) >= 0
    })
    var selected = Object.assign({}, draft.tools)
    selected.editorId = roles.indexOf('editor') >= 0 ? selected.editorId || Profiles.preferred(tools, 'editors', 'editorId') : null
    selected.agentId = roles.indexOf('agent') >= 0 ? selected.agentId || Profiles.preferred(tools, 'agents', 'agentId') : null
    selected.terminalId = roles.indexOf('terminal') >= 0 || roles.indexOf('agent') >= 0 || selected.editorId === 'nvim' ? selected.terminalId || Profiles.preferred(tools, 'terminals', 'terminalId') : null
    draft = Object.assign({}, draft, {
      roles: roles,
      tools: selected
    })
    fieldError = ''
  }
  // Explicit save resolves null defaults but preserves original edit concurrency guard.
  function save(): void {
    if (displayOnly || pending)
      return
    var resolved = Profiles.resolve(draft, tools)
    fieldError = !draft.name.trim() || /[\x00-\x1f\x7f]/.test(draft.name) ? 'Enter a profile name without control characters.' : resolved.error
    if (fieldError)
      return
    saveRequested(Object.assign({}, draft, {
      tools: resolved.tools
    }), expectedProfileRevision)
  }
  spacing: Style.space(10)
  Aranea.UiLabel {
    text: editor.draft.id ? 'Edit profile' : 'New profile'
    font.bold: true
  }
  Aranea.UiLabel {
    text: 'Profile name'
  }
  Ui.TextField {
    objectName: 'profileName'
    Layout.fillWidth: true
    text: editor.draft.name
    enabled: !editor.displayOnly && !editor.pending
    Accessible.name: 'Profile name'
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: Style.font.body
    onTextEdited: editor.setName(text)
  }
  Flow {
    Layout.fillWidth: true
    spacing: Style.space(8)
    Repeater {
      model: [
        {
          id: 'editor',
          label: 'Editor'
        },
        {
          id: 'terminal',
          label: 'Terminal'
        },
        {
          id: 'agent',
          label: 'Agent'
        }
      ]
      Aranea.ActionButton {
        required property var modelData
        text: modelData.label
        selected: editor.draft.roles.indexOf(modelData.id) >= 0
        enabled: !editor.displayOnly && !editor.pending
        pointerGate: editor.pointerGate
        onClicked: editor.toggleRole(modelData.id)
      }
    }
  }
  ColumnLayout {
    Layout.fillWidth: true
    visible: editor.draft.roles.indexOf('editor') >= 0
    Aranea.UiLabel {
      text: 'Editor'
    }
    Repeater {
      model: Profiles.choices(editor.tools, 'editors')
      Aranea.ActionButton {
        required property var modelData
        text: modelData.label || modelData.id
        selected: editor.draft.tools.editorId === modelData.id || !editor.draft.tools.editorId && Profiles.preferred(editor.tools, 'editors', 'editorId') === modelData.id
        enabled: !editor.displayOnly && !editor.pending
        pointerGate: editor.pointerGate
        onClicked: editor.setTool('editorId', modelData.id)
      }
    }
  }
  ColumnLayout {
    objectName: 'profileAgentSettings'
    Layout.fillWidth: true
    visible: editor.draft.roles.indexOf('agent') >= 0
    Aranea.UiLabel {
      text: 'Agent provider'
    }
    Repeater {
      model: Profiles.choices(editor.tools, 'agents')
      Aranea.ActionButton {
        required property var modelData
        text: modelData.label || modelData.id
        selected: editor.draft.tools.agentId === modelData.id || !editor.draft.tools.agentId && Profiles.preferred(editor.tools, 'agents', 'agentId') === modelData.id
        enabled: !editor.displayOnly && !editor.pending
        pointerGate: editor.pointerGate
        onClicked: editor.setTool('agentId', modelData.id)
      }
    }
  }
  ColumnLayout {
    Layout.fillWidth: true
    visible: editor.needsTerminal
    Aranea.UiLabel {
      objectName: 'profileTerminalHint'
      Layout.fillWidth: true
      text: 'Neovim and Agent run in your selected terminal.'
      visible: editor.draft.roles.indexOf('agent') >= 0 || editor.draft.roles.indexOf('editor') >= 0 && (editor.draft.tools.editorId || Profiles.preferred(editor.tools, 'editors', 'editorId')) === 'nvim'
    }
    Aranea.UiLabel {
      text: 'Terminal'
    }
    Repeater {
      model: Profiles.choices(editor.tools, 'terminals')
      Aranea.ActionButton {
        required property var modelData
        text: modelData.label || modelData.id
        selected: editor.draft.tools.terminalId === modelData.id || !editor.draft.tools.terminalId && Profiles.preferred(editor.tools, 'terminals', 'terminalId') === modelData.id
        enabled: !editor.displayOnly && !editor.pending
        pointerGate: editor.pointerGate
        onClicked: editor.setTool('terminalId', modelData.id)
      }
    }
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    text: editor.fieldError || Profiles.resolve(editor.draft, editor.tools).error
    visible: !!text
    color: Aranea.DesignTokens.attention
  }
  Flow {
    Layout.fillWidth: true
    spacing: Style.space(8)
    Aranea.ActionButton {
      text: 'Save profile'
      variant: 'primary'
      enabled: !editor.displayOnly && !editor.pending
      pointerGate: editor.pointerGate
      onClicked: editor.save()
    }
    Aranea.ActionButton {
      text: 'Discard'
      enabled: !editor.displayOnly && !editor.pending
      pointerGate: editor.pointerGate
      onClicked: editor.cancelRequested()
    }
  }
}
