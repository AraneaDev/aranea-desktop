// Pure bounded task details and stable action controls; all effects belong to the host.
// Host font tokens are dynamic QObject properties.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea
import "AgentTasksLogic.js" as Logic

Item {
  id: details
  // Exact task projection supplied by the list.
  property var row: null
  // Retained accepted operation for this task only.
  property var operation: null
  // Actionable client or owner error.
  property var error: null
  // Client submission/observation blocks new mutations.
  property bool pending: false
  // Available height including the scrollable actions.
  property real maxHeight: Style.space(640)
  // Stable action under keyboard navigation.
  property string cursorKind: ''
  // First activation only reveals this cursor.
  property bool keyboardCursor: false
  // Layout movement refuses unsettled pointer choices.
  property real layoutChangedAt: 0
  // Independent accepted and observed outcome projection.
  readonly property var outcome: Logic.operationView(operation, error, pending)
  // Fixed current action IDs in visual order.
  readonly property var actionKinds: {
    var kinds = ['back']
    if (row && row.primary.kind && (row.primary.local || !pending && !outcome.protected))
      kinds.unshift(row.primary.kind)
    if (row && row.assigned && !pending && !outcome.protected && kinds.indexOf('open-checkout') < 0)
      kinds.push('open-checkout')
    if (row && row.secondary && row.secondary.kind && !pending && !outcome.protected)
      kinds.push(row.secondary.kind)
    if (outcome.canReobserve)
      kinds.push('reobserve')
    if (outcome.canReconnect)
      kinds.push('reconnect')
    if (row && row.canDismiss && !pending && !outcome.protected)
      kinds.push('dismiss')
    if (row && !row.assigned)
      kinds.push('setup')
    return kinds
  }
  // Identity includes task and action availability, preventing changed release/Enter.
  readonly property string identity: (row ? row.key : '') + '\n' + actionKinds.join('\n') + '\n' + (operation ? [operation.id, operation.ownerId, operation.attempt].join(':') : '')
  // Scroll exposure supports inert captures and reachability checks.
  readonly property alias scroll: scroller
  // Every control emits one fixed kind and exact task identity.
  signal action(string kind, string taskId)
  onIdentityChanged: {
    keyboardCursor = false
    layoutChangedAt = Date.now()
    if (actionKinds.indexOf(cursorKind) < 0)
      cursorKind = ''
  }
  // Human labels for the fixed action enum.
  function label(kind) {
    if (row && kind === row.primary.kind)
      return row.primary.label
    if (row && row.secondary && kind === row.secondary.kind)
      return row.secondary.label
    return {
      'back': 'Back to tasks',
      'open-checkout': 'Open checkout',
      'reobserve': 'Check session again',
      'reconnect': 'Reconnect observation',
      'dismiss': 'Dismiss task',
      'setup': 'Project settings'
    }[kind] || kind
  }
  // Refuse changed or unsettled action identities.
  function activateKind(kind, pointer) {
    if (!row || actionKinds.indexOf(kind) < 0 || pointer && Date.now() - layoutChangedAt < 300)
      return false
    if (pointer)
      keyboardCursor = false
    if (kind === 'inspect-result' || kind === 'inspect-failure')
      inspectReport(kind)
    action(kind, row.key)
    return true
  }
  // Fixed local report inspection scrolls bounded plaintext without owner I/O.
  function inspectReport(kind) {
    var target = kind === 'inspect-failure' && !(row && row.result) ? diagnosticsSection : resultSection
    scroller.contentY = Math.max(0, Math.min(scroller.contentHeight - scroller.height, target.y))
  }
  // Tab switches and panel reopen require a fresh keyboard reveal.
  function disarmCursor() {
    keyboardCursor = false
  }
  // First Enter reveals the primary action; navigation preserves fixed IDs.
  function navigate(direction) {
    var next = Logic.step(actionKinds, cursorKind, keyboardCursor, direction)
    cursorKind = next.key
    keyboardCursor = true
    if (next.activate) {
      activateKind(cursorKind, false)
      if (cursorKind === 'inspect-result' || cursorKind === 'inspect-failure')
        return
    }
    scroller.contentY = Math.max(0, scroller.contentHeight - scroller.height)
  }
  implicitHeight: Math.min(maxHeight, body.implicitHeight)
  height: implicitHeight
  clip: true
  Flickable {
    id: scroller
    anchors.fill: parent
    contentWidth: width
    contentHeight: body.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    onContentYChanged: details.layoutChangedAt = Date.now()
    Column {
      id: body
      onHeightChanged: details.layoutChangedAt = Date.now()
      width: scroller.width
      spacing: Style.space(10)
      Text {
        objectName: 'detailsSummary'
        width: parent.width
        text: details.row ? details.row.summary : ''
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        font.family: Aranea.Typography.uiFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        width: parent.width
        text: details.row ? details.row.providerLabel + ' · ' + details.row.stateLabel + '\nReported: ' + details.row.reportedLabel + ' · ' + details.row.freshnessLabel : ''
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
      }
      Text {
        objectName: 'lastReportTime'
        width: parent.width
        text: details.row ? [details.row.lastReportTime, details.row.lastReportLabel].filter(Boolean).join('\n') : ''
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
      }
      TextEdit {
        width: parent.width
        text: details.row ? details.row.context : ''
        textFormat: TextEdit.PlainText
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.WrapAnywhere
        color: Aranea.DesignTokens.foreground
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: Style.font.body
      }
      Text {
        text: 'Reported result'
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        id: resultSection
        objectName: 'reportedResult'
        width: parent.width
        text: details.row ? details.row.result || 'No result reported' : ''
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
      }
      Text {
        text: 'Question / blockers'
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        objectName: 'reportedQuestion'
        width: parent.width
        text: details.row ? details.row.question || 'No question reported' : ''
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
      }
      Text {
        width: parent.width
        visible: text !== ''
        text: details.row ? details.row.blockers : ''
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
      }
      Text {
        text: 'Diagnostics'
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        id: diagnosticsSection
        objectName: 'reportedDiagnostics'
        width: parent.width
        text: details.row ? details.row.diagnostics || 'No diagnostics reported' : ''
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
      }
      Text {
        objectName: 'reportedVerification'
        width: parent.width
        text: details.row ? details.row.verificationLabel : ''
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        width: parent.width
        visible: text !== ''
        text: details.row ? [details.row.verificationSummary, details.row.verificationCommands].filter(Boolean).join('\n') : ''
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
      }
      Text {
        objectName: 'sessionUnavailable'
        width: parent.width
        visible: details.row && !details.row.primary.kind
        text: details.row && !details.row.assigned ? 'Register this exact checkout in Project settings to enable checkout actions.' : 'No proven session is available. Enable the provider adapter explicitly; manual reports do not prove a hosting terminal.'
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
      }
      Text {
        objectName: 'hostingTerminalNote'
        width: parent.width
        text: 'Go to session focuses the hosting terminal. It cannot select a terminal pane or tmux window. Reported results and verification come from the agent.'
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        opacity: 0.65
        font.pixelSize: Style.font.body
      }
      Text {
        objectName: 'operationStatus'
        width: parent.width
        visible: text !== ''
        text: details.outcome.label
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.attention
        font.pixelSize: Style.font.body
      }
      Text {
        objectName: 'operationSteps'
        width: parent.width
        visible: text !== ''
        text: details.outcome.steps
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
      }
      Text {
        objectName: 'operationError'
        width: parent.width
        visible: text !== ''
        text: [details.outcome.message, details.outcome.recovery].filter(Boolean).join('\n')
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
      }
      Text {
        width: parent.width
        visible: details.outcome.protected
        text: 'Acceptance is uncertain. Check the existing terminal; reconnect only reads the retained operation and never launches again.'
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
      }
      TextEdit {
        objectName: 'resumeCommand'
        width: parent.width
        visible: text !== ''
        text: details.row ? details.row.resumeCommand : ''
        readOnly: true
        selectByMouse: true
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.WrapAnywhere
        color: Aranea.DesignTokens.foreground
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: Style.font.body
      }
      Flow {
        width: parent.width
        spacing: Style.space(8)
        Repeater {
          model: details.actionKinds
          Aranea.FilamentPill {
            id: control
            required property string modelData
            property string pressedIdentity: ''
            objectName: 'taskAction'
            width: Math.min(implicitWidth, parent.width)
            refined: true
            text: details.label(modelData)
            hasCursor: details.keyboardCursor && details.cursorKind === modelData
            onPressed: pressedIdentity = details.identity
            onPressCanceled: pressedIdentity = ''
            onClicked: {
              if (pressedIdentity && pressedIdentity !== details.identity)
                return
              details.activateKind(modelData, !!pressedIdentity)
              pressedIdentity = ''
            }
          }
        }
      }
      Text {
        width: parent.width
        text: '↑↓ / j k actions · enter select · escape back'
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        opacity: 0.55
        font.pixelSize: Style.font.body
      }
    }
  }
}
