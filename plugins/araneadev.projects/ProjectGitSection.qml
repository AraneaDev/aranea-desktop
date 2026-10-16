// Largest overview group: read-only Git facts and optional path details.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "ProjectOverview.js" as Overview
import qs.Commons
import "../araneadev.shared" as Aranea

ProjectSectionCard {
  id: section
  // Exact selected-checkout Git observation, or null.
  property var git: null
  // Latest read failure, independent of retained observations.
  property var error: null
  // Read-only observation progress.
  property bool loading: false
  // Capture boundary refuses every external action.
  property bool displayOnly: false
  // Shared pointer settlement gate for moving content.
  property var pointerGate: null
  // Local expansion reveals optional history or file paths.
  property bool expanded: false
  // Injected presentation clock for stale-state copy.
  property real nowMs: Date.now()
  // Running explicit Git command for this checkout: '', 'fetch' or 'pull'.
  property string commandPending: ''
  // Last fetch or pull failure for this checkout as {message, recovery}, or null.
  property var commandError: null
  // Any Git command is running, for this or another checkout; starting is refused.
  property bool commandBusy: false
  // Pull needs a branch with an upstream.
  readonly property bool canPull: !!git && !git.detached && !!git.upstream
  // Nothing to pull from the last observed upstream.
  readonly property bool upToDate: canPull && git.behind === 0
  // Explicit read-only refresh request.
  signal refreshRequested
  // Explicit network fetch request.
  signal fetchRequested
  // Explicit fast-forward pull request.
  signal pullRequested
  onGitChanged: if (!git)
    expanded = false
  RowLayout {
    Layout.fillWidth: true
    Aranea.UiLabel {
      text: 'Git'
      font.pixelSize: Style.font.heading
      font.bold: true
      Layout.fillWidth: true
    }
    Aranea.ActionButton {
      text: section.loading ? 'Reading…' : 'Refresh'
      enabled: !section.displayOnly && !section.loading
      pointerGate: section.pointerGate
      onClicked: section.refreshRequested()
    }
    Aranea.ActionButton {
      objectName: 'projectGitFetch'
      text: section.commandPending === 'fetch' ? 'Fetching…' : 'Fetch'
      enabled: !section.displayOnly && !section.loading && section.commandPending === '' && !section.commandBusy
      pointerGate: section.pointerGate
      onClicked: section.fetchRequested()
    }
    Aranea.ActionButton {
      objectName: 'projectGitPull'
      text: section.commandPending === 'pull' ? 'Pulling…' : section.upToDate ? 'Up to date' : 'Pull'
      enabled: !section.displayOnly && !section.loading && section.commandPending === '' && !section.commandBusy && section.canPull && !section.upToDate
      pointerGate: section.pointerGate
      onClicked: section.pullRequested()
    }
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    text: section.git ? (section.git.detached ? 'Detached HEAD' : section.git.branch || 'Branch unavailable') : section.loading ? 'Reading selected checkout…' : 'Git state not available. Refresh to read this checkout.'
    font.pixelSize: Style.font.body
    font.bold: true
  }
  Aranea.UiLabel {
    objectName: 'projectGitError'
    Layout.fillWidth: true
    visible: !!section.error || !!section.commandError
    text: section.commandError ? section.commandError.message + ' ' + (section.commandError.recovery || '') : section.error ? section.error.message + (section.git ? ' · Showing last observation.' : '') : ''
    color: Aranea.DesignTokens.urgent
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: !!section.git
    text: {
      var c = section.git ? section.git.counts || {} : {}
      return (c.staged || 0) + ' staged · ' + (c.unstaged || 0) + ' unstaged · ' + (c.untracked || 0) + ' untracked · ' + (c.conflicts || 0) + ' conflicts'
    }
    font.pixelSize: Style.font.body
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: !!section.git
    text: {
      if (!section.git || !section.git.upstream)
        return 'No upstream configured'
      var comparable = typeof section.git.ahead === 'number' && typeof section.git.behind === 'number'
      return (comparable ? section.git.ahead + ' ahead · ' + section.git.behind + ' behind ' : 'Comparison unavailable · ') + section.git.upstream + ' · Local refs; no remote fetch'
    }
    opacity: 0.7
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: !!section.git
    text: section.git ? 'Observed ' + Overview.ageLabel(section.git.observedAt, Math.max(section.nowMs, Date.now())) + (section.nowMs - section.git.observedAt > 30000 ? ' · May be stale' : '') : ''
    opacity: 0.6
    ToolTip.visible: observationHover.hovered
    ToolTip.text: section.git ? new Date(section.git.observedAt).toLocaleString() : ''
    HoverHandler {
      id: observationHover
    }
  }
  Aranea.ActionButton {
    text: section.expanded ? 'Hide changes' : 'Changes'
    visible: !!section.git && (section.git.files || []).length > 0
    pointerGate: section.pointerGate
    onClicked: section.expanded = !section.expanded
  }
  ColumnLayout {
    Layout.fillWidth: true
    visible: section.expanded
    Aranea.UiLabel {
      Layout.fillWidth: true
      text: 'Counts describe files and can overlap.'
      opacity: 0.6
    }
    Repeater {
      model: [
        {
          key: 'conflict',
          label: 'Conflicts'
        },
        {
          key: 'staged',
          label: 'Staged'
        },
        {
          key: 'unstaged',
          label: 'Unstaged'
        },
        {
          key: 'untracked',
          label: 'Untracked'
        }
      ]
      ColumnLayout {
        id: group
        required property var modelData
        readonly property var files: section.git ? Overview.gitFiles(section.git.files || [], group.modelData.key) : []
        Layout.fillWidth: true
        visible: files.length > 0
        Aranea.UiLabel {
          text: group.modelData.label
          font.bold: true
        }
        Repeater {
          model: group.files
          Aranea.UiLabel {
            required property var modelData
            Layout.fillWidth: true
            text: JSON.stringify(modelData.path)
            technical: true
            wrapMode: Text.WrapAnywhere
          }
        }
      }
    }
    Aranea.UiLabel {
      Layout.fillWidth: true
      visible: !!section.git && section.git.truncated === true
      text: 'Path list truncated; file counts cover the checkout.'
    }
  }
}
