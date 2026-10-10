// Immutable exact-run evidence and explicit controls; only the shared client performs I/O.
pragma ComponentBehavior: Bound
// Host font tokens are runtime QObject properties.
// qmllint disable missing-property
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea
import "../araneadev.projects/ProjectActionRecords.js" as Records

ColumnLayout {
  id: details
  // Shared client, never a second launcher or desktop adapter.
  property var client: null
  // Retained backend run with immutable definition snapshot.
  property var run: null
  // Exact registered checkout resolved by its ID, never a fallback.
  property var checkout: null
  // Captures prohibit all effects, including reads and focus requests.
  property bool displayOnly: false
  // Existing project owner's focus authority.
  property var projectClient: null
  // Shared pointer settling gate.
  property var pointerGate: null
  // Identity remembered before pointer press; release cannot transfer to another run.
  property string pressedIdentity: ''
  // Identity armed by keyboard focus or one reveal activation.
  property string keyboardIdentity: ''
  // Honest process/readiness label also retains terminal cleanup uncertainty.
  readonly property string statusText: Records.runLabel(run)
  // Restart must refer to the same currently displayed saved action revision.
  readonly property var currentDefinition: run && client ? Records.definitions(client.snapshot, run.projectId).filter(function (definition) {
    return definition.id === run.actionId
  })[0] || null : null
  // Restart is impossible while launch or cleanup remains uncertain.
  readonly property bool restartAllowed: !!run && !!currentDefinition && currentDefinition.revision === run.definitionRevision && !run.submissionUnconfirmed && run.processState !== 'unconfirmed'
  // Render bounded output only for the exact attached run, never another run's logs.
  readonly property string outputText: client && run && client.runId === run.id ? boundedOutput(client.output) : ''
  // UTF-8 byte limit also protects renders driven by isolated capture fixtures.
  function boundedOutput(text: string): string {
    var bytes = 0
    var index = 0
    for (; index < text.length; index++) {
      var code = text.charCodeAt(index)
      var size = code < 128 ? 1 : code < 2048 ? 2 : 3
      if (code >= 0xd800 && code <= 0xdbff && index + 1 < text.length && text.charCodeAt(index + 1) >= 0xdc00 && text.charCodeAt(index + 1) <= 0xdfff)
        size = 4
      if (bytes + size > 262144)
        break
      bytes += size
      if (size === 4)
        index++
    }
    return text.slice(0, index)
  }
  // Commands show literal argument boundaries, including empty arguments.
  readonly property string commandText: run && run.definitionSnapshot ? run.definitionSnapshot.argv.map(function (arg) {
    return JSON.stringify(arg)
  }).join(' ') : ''
  // Stable run identity spans refreshes but excludes unrelated/replaced records.
  function identity(): string {
    return run ? [run.projectId, run.checkoutId, run.id, run.definitionRevision, run.definitionHash].join('|') : ''
  }
  // Remember an exact press target before a view or checkout can change.
  function rememberRun(id: string): void {
    pressedIdentity = run && run.id === id ? identity() : '!invalid'
  }
  // A changed row/checkout/revision never authorizes the newly displayed control.
  function releaseRun(method: string, id: string): void {
    var remembered = pressedIdentity
    pressedIdentity = ''
    if (remembered && remembered === identity())
      perform(method, id)
  }
  // First activation after a replaced focused row reveals rather than executing it.
  function activateRun(method: string, id: string): void {
    if (keyboardIdentity !== identity()) {
      keyboardIdentity = identity()
      return
    }
    perform(method, id)
  }
  // Controls always carry the displayed immutable ID and exact selected checkout.
  function perform(method: string, id: string): void {
    if (displayOnly || !client || client.captureActive || client.pending || !run || id !== run.id || client.projectId !== run.projectId || client.checkoutId !== run.checkoutId)
      return
    if (method === 'focus') {
      if (projectClient && projectClient.available && !projectClient.pending)
        projectClient.request({
          projectId: run.projectId,
          checkoutId: run.checkoutId
        })
      return
    }
    if (!client.currentRun || client.currentRun.id !== id)
      return
    if (method === 'refresh')
      client.refreshRun(id)
    else if (method === 'logs')
      client.logs(id)
    else if (method === 'stop' && Records.protectedRun(run))
      client.stop(id)
    else if (method === 'restart' && restartAllowed && !client.submissionUncertain)
      client.restart(id)
    else if (method === 'preview' && Records.canOpenPreview(run))
      client.openPreview(id)
  }
  spacing: Style.space(8)
  visible: !!run
  SettingsLabel {
    Layout.fillWidth: true
    text: details.run && details.run.definitionSnapshot ? details.run.definitionSnapshot.name : 'Retained run'
    font.bold: true
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  SettingsLabel {
    objectName: 'actionRunStatus'
    Layout.fillWidth: true
    text: details.statusText
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: 'Checkout: ' + (details.checkout ? details.checkout.path : 'Unavailable') + ' · ' + (details.run ? details.run.checkoutId : '')
    technical: true
    wrapMode: Text.WrapAnywhere
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: 'Command: ' + details.commandText
    technical: true
    wrapMode: Text.WrapAnywhere
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: 'Working folder: ' + (details.run ? details.run.cwd || 'Not resolved' : '')
    technical: true
    wrapMode: Text.WrapAnywhere
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: details.run ? 'Run: ' + details.run.id + ' · Receipt: ' + (details.run.createdAt ? new Date(details.run.createdAt * 1000).toLocaleString() : 'Unavailable') + ' · Outcome: ' + (details.run.outcome || 'Awaiting observation') : ''
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !!details.run && (details.run.exitCode !== null && details.run.exitCode !== undefined || !!details.run.exitSignal)
    text: details.run ? 'Process result: exit ' + (details.run.exitCode === null || details.run.exitCode === undefined ? 'unknown' : details.run.exitCode) + (details.run.exitSignal ? ' · signal ' + details.run.exitSignal : '') : ''
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !!details.run && !!details.run.error
    text: details.run && details.run.error ? (details.run.error.message || details.run.error.code) + (details.run.error.recovery ? ' ' + details.run.error.recovery : '') : ''
    color: Aranea.DesignTokens.attention
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !!details.run && (!details.currentDefinition || details.currentDefinition.revision !== details.run.definitionRevision)
    text: 'Action changed. Review its current command, then Run or Start it.'
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  Flow {
    Layout.fillWidth: true
    spacing: Style.space(8)
    Repeater {
      model: [
        {
          method: 'refresh',
          label: 'Refresh'
        },
        {
          method: 'logs',
          label: 'View logs'
        },
        {
          method: 'stop',
          label: 'Stop / Cancel'
        },
        {
          method: 'restart',
          label: 'Restart explicitly'
        },
        {
          method: 'preview',
          label: 'Open preview'
        },
        {
          method: 'focus',
          label: 'Focus project'
        }
      ]
      SettingsButton {
        id: control
        required property var modelData
        objectName: 'actionRun:' + modelData.method
        text: modelData.label
        pointerGate: details.pointerGate
        enabled: !details.displayOnly && !!details.client && !details.client.captureActive && !details.client.pending && !!details.run && (modelData.method !== 'stop' || Records.protectedRun(details.run)) && (modelData.method !== 'restart' || details.restartAllowed && !details.client.submissionUncertain) && (modelData.method !== 'preview' || Records.canOpenPreview(details.run)) && (modelData.method !== 'focus' || !!details.projectClient && details.projectClient.available && !details.projectClient.pending)
        onActiveFocusChanged: if (activeFocus)
          details.keyboardIdentity = details.identity()
        onPressed: details.rememberRun(details.run.id)
        onPressCanceled: details.pressedIdentity = ''
        onClicked: {
          if (details.pressedIdentity)
            details.releaseRun(control.modelData.method, details.run.id)
          else
            details.activateRun(control.modelData.method, details.run.id)
        }
      }
    }
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: 'Output comes from the local user journal. Retention follows the system journal policy.'
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  SettingsLabel {
    objectName: 'actionOutputTruncated'
    Layout.fillWidth: true
    visible: !!details.client && (details.client.truncated || details.client.output.length > details.outputText.length)
    text: 'Output truncated to the available bounded journal excerpt.'
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  ScrollView {
    Layout.fillWidth: true
    Layout.preferredHeight: Style.space(180)
    visible: !!details.outputText
    clip: true
    TextArea {
      objectName: 'actionRunOutput'
      text: details.outputText
      readOnly: true
      selectByMouse: true
      textFormat: TextEdit.PlainText
      wrapMode: TextEdit.WrapAnywhere
      font.family: Aranea.Typography.technicalFamily
      font.pixelSize: Style.font.caption
      color: Color.foreground
      background: Rectangle {
        radius: Style.space(3)
        color: Util.alpha(Color.foreground, 0.065)
      }
    }
  }
}
