// Selected project identity and its primary action stay separate from settings.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import "../araneadev.shared" as Aranea

ColumnLayout {
  id: header
  objectName: 'projectHeader'
  // Current saved project identity; this view never changes registration.
  property var project: null
  // Observed workspace bindings supplied by the persistent owner.
  property var bindings: []
  // Whether the live owner can open workspace tools.
  property bool openAvailable: false
  // A project operation is pending; duplicate Open is disabled.
  property bool pending: false
  // Inert captures refuse workspace activation.
  property bool displayOnly: false
  // Shared pointer settling gate for content that moves during refresh.
  property var pointerGate: null
  // Resolve the saved selected checkout, falling back to its primary listing.
  readonly property var checkout: project ? (project.checkouts || []).filter(function (c) {
    return c.id === header.project.lastCheckoutId
  })[0] || (project.checkouts || [])[0] || null : null
  // Match only the observed workspace for the displayed project and checkout.
  readonly property var binding: project ? bindings.filter(function (b) {
    return b.projectId === header.project.id && (!header.checkout || b.checkoutId === header.checkout.id)
  })[0] || null : null
  // Request ordinary Open through the existing typed owner boundary.
  signal openRequested
  // Installed adapters and supported defaults from the current tool probe.
  property var tools: ({})
  // Optional unclipped menu layer supplied by the window surface.
  property Item menuHost: null
  // Surface geometry epoch updates mapped popup anchors.
  property real menuRevision: 0
  // Suggestion result for this project (AgentSuggestion.suggest), or null.
  property var agentChoice: null
  // Display labels for the saved editor and terminal.
  property var toolLabels: ({})
  // Saved default roles; legacy registrations open editor and terminal.
  readonly property var openRoles: project && Array.isArray(project.openRoles) ? project.openRoles : ['editor', 'terminal']
  // Installed agent options in suggestion order.
  readonly property var agentOptions: {
    var choice = agentChoice || {
      options: []
    }
    return (choice.options || []).filter(function (o) {
      return o.available
    }).sort(function (a, b) {
      return (b.id === choice.suggestedId) - (a.id === choice.suggestedId)
    })
  }
  // Compact provider label used by the saved-role summary.
  readonly property string suggestedLabel: agentOptions.length ? agentOptions[0].label.replace(' Code', '') : ''
  // Plain summary of what the primary Open does.
  readonly property string opensText: 'Opens ' + openRoles.map(function (role) {
    return role === 'agent' ? 'Agent' + (header.suggestedLabel ? ' (' + header.suggestedLabel + ')' : '') : role.charAt(0).toUpperCase() + role.slice(1)
  }).join(' + ')
  // One-off owner request for this project's selected checkout.
  signal oneOffRequested(var payload)
  // Immediate default-roles save (canonical order).
  signal defaultRolesRequested(var roles)
  // Resolve the saved adapter only through the current installed supported probe.
  function roleAvailable(role: string): bool {
    var saved = project && project.tools || {}, defaults = tools.defaults || {}
    var id = saved[role + 'Id'] || defaults[role + 'Id']
    return (tools[role === 'editor' ? 'editors' : 'terminals'] || []).some(function (tool) {
      return tool.id === id && tool.available === true && tool.supported === true
    })
  }
  // Menu rows for the split button.
  function menuEntries(): var {
    var roles = openRoles, rows = [
      {
        kind: 'header',
        label: 'Opens by default'
      }
    ];
    ['editor', 'terminal', 'agent'].forEach(function (role) {
      var checked = roles.indexOf(role) >= 0
      var last = checked && roles.length === 1
      var noAgent = role === 'agent' && header.agentOptions.length === 0
      var noHost = role === 'agent' && !header.roleAvailable('terminal')
      var unavailable = role !== 'agent' && !header.roleAvailable(role)
      rows.push({
        kind: 'check',
        key: 'role:' + role,
        label: role === 'agent' ? 'Agent' : role === 'editor' ? 'Editor' : 'Terminal',
        detail: role === 'agent' ? (noAgent ? 'Install Claude Code or Codex to start agents here.' : noHost ? 'Agents run in a terminal. Choose one in Preferences.' : header.suggestedLabel + ' · Suggested · ' + header.agentOptions[0].reason) : header.toolLabels[role] || '',
        checked: checked,
        enabled: !header.pending && !last && !noAgent && !noHost && !unavailable,
        tooltip: last ? 'Open needs at least one tool' : unavailable ? 'Choose an installed ' + role + ' in Preferences.' : ''
      })
    })
    rows.push({
      kind: 'separator'
    }, {
      kind: 'header',
      label: 'Just open one'
    })
    header.agentOptions.forEach(function (option, index) {
      rows.push({
        kind: 'action',
        key: 'start:' + option.id,
        label: 'Start ' + option.label.replace(' Code', ''),
        detail: (index === 0 ? 'Suggested · ' : '') + option.reason,
        enabled: !header.pending && header.roleAvailable('terminal')
      })
    })
    rows.push({
      kind: 'action',
      key: 'only:terminal',
      label: 'Terminal only',
      detail: header.toolLabels.terminal || '',
      enabled: !header.pending && header.roleAvailable('terminal')
    }, {
      kind: 'action',
      key: 'only:editor',
      label: 'Editor only',
      detail: header.toolLabels.editor || '',
      enabled: !header.pending && header.roleAvailable('editor')
    })
    return rows
  }
  // Route one menu key to a default save or a one-off request.
  function choose(key: string): void {
    if (!project || displayOnly || pending || !openAvailable)
      return
    var selected = menuEntries().filter(function (row) {
      return row.key === key
    })[0]
    if (!selected || selected.enabled === false)
      return
    var parts = key.split(':'), base = {
      projectId: project.id,
      checkoutId: checkout ? checkout.id : project.lastCheckoutId
    }
    if (parts[0] === 'role') {
      var next = ['editor', 'terminal', 'agent'].filter(function (role) {
        return role === parts[1] ? !selected.checked : openRoles.indexOf(role) >= 0
      })
      defaultRolesRequested(next)
    } else if (parts[0] === 'start')
      oneOffRequested(Object.assign(base, {
        roles: ['agent'],
        newWindowRole: 'agent',
        agentId: parts[1]
      }))
    else if (parts[0] === 'only')
      oneOffRequested(Object.assign(base, {
        roles: [parts[1]]
      }))
  }
  z: openSplit.menuOpen ? 10 : 0
  spacing: Style.space(8)
  GridLayout {
    Layout.fillWidth: true
    columns: header.width < Style.space(440) ? 1 : 2
    columnSpacing: Style.space(12)
    rowSpacing: Style.space(8)
    Aranea.UiLabel {
      Layout.fillWidth: true
      text: header.project ? header.project.name : ''
      font.pixelSize: Style.font.heading
      font.bold: true
      maximumLineCount: header.width < Style.space(440) ? 3 : 2
      elide: Text.ElideRight
      ToolTip.visible: nameHover.hovered
      ToolTip.text: text
      HoverHandler {
        id: nameHover
      }
    }
    Aranea.SplitButton {
      id: openSplit
      objectName: 'projectPrimaryOpen'
      Layout.fillWidth: header.width < Style.space(440)
      text: header.pending ? 'Preparing…' : 'Open workspace'
      enabled: !header.displayOnly && !header.pending && header.openAvailable
      pointerGate: header.pointerGate
      menuHost: header.menuHost
      menuRevision: header.menuRevision
      entries: header.menuEntries()
      onClicked: header.openRequested()
      onTriggered: function (key) {
        header.choose(key)
      }
    }
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    text: header.checkout ? header.checkout.path : 'No registered checkout'
    technical: true
    opacity: 0.7
    wrapMode: Text.NoWrap
    elide: Text.ElideMiddle
    ToolTip.visible: pathHover.hovered
    ToolTip.text: text
    HoverHandler {
      id: pathHover
    }
  }
  Flow {
    Layout.fillWidth: true
    spacing: Style.space(12)
    Aranea.UiLabel {
      objectName: 'projectOpensText'
      width: Math.min(implicitWidth, header.width)
      text: header.opensText
      opacity: 0.8
    }
    Aranea.UiLabel {
      objectName: 'projectBranch'
      width: Math.min(implicitWidth, header.width)
      text: header.checkout ? 'Branch · ' + (header.checkout.branch || 'detached') : ''
      opacity: 0.8
    }
    Aranea.UiLabel {
      width: Math.min(implicitWidth, header.width)
      text: header.binding ? 'Workspace ' + header.binding.workspaceId : header.project && header.project.workspaceMode === 'current' ? 'Uses current workspace' : 'Dedicated workspace'
      opacity: 0.8
    }
    Aranea.UiLabel {
      width: Math.min(implicitWidth, header.width)
      text: header.openAvailable ? 'Ready to open' : 'Workspace opening unavailable'
      color: header.openAvailable ? Aranea.DesignTokens.accent : Aranea.DesignTokens.attention
    }
  }
}
