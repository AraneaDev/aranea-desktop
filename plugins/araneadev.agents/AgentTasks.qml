// Inert Tasks list/detail composition; the host alone submits fixed owner actions.
// Host font tokens are dynamic QObject properties.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea
import "AgentTasksLogic.js" as Logic

Item {
  id: tasks
  // Projected activity snapshot supplied by an injected or real client.
  property var snapshot: ({
      tasks: []
    })
  // Read-only exact project/checkout labels.
  property var projectSnapshot: ({
      projects: []
    })
  // Capture state is exposed to hosts; this view has no I/O.
  property bool captureActive: false
  // Client structured error; the previous snapshot remains displayed.
  property var error: null
  // One client cannot submit another action while observing.
  property bool pending: false
  // Retained client operation, independent of current selection.
  property var operation: null
  // Exact accepted owner-loss records retained by the presentation host.
  property var uncertainOperations: []
  // Available list/details height.
  property real maxHeight: Style.space(640)
  // Injectable wall clock only formats report receipt ages.
  property double nowMs: Date.now()
  // Stable selected detail task, never a row position.
  property string selectedId: ''
  // Stable keyboard row identity.
  property string cursorId: ''
  // First Enter reveals the cursor.
  property bool keyboardCursor: false
  // Rows are attention-first immutable task projections.
  readonly property var taskRows: Logic.rows(snapshot, projectSnapshot, nowMs)
  // Selection is resolved by identity after every sort/refresh.
  readonly property var selectedRow: taskRows.filter(function (r) {
    return r.key === selectedId
  })[0] || null
  // Relevant operation only; another task never inherits controls.
  readonly property var selectedOperation: operationFor(selectedId)
  // Row identity or content changes stamp pointer settling.
  readonly property string layoutSignature: JSON.stringify(taskRows)
  // Pointer clicks cannot adopt a layout that just changed.
  property real layoutChangedAt: 0
  // Scroll exposure for captures and narrow-layout tests.
  readonly property alias scroll: listScroll
  // Fixed action kinds and stable task IDs, never shell command text.
  signal action(string kind, string taskId)
  onLayoutSignatureChanged: {
    layoutChangedAt = Date.now()
    if (!Logic.reconcileSelection(cursorId, taskRows).key) {
      cursorId = ''
      keyboardCursor = false
    }
    if (selectedId && !selectedRow) {
      selectedId = ''
      keyboardCursor = false
    }
  }
  // Recover retained exact task operations even after observing another task.
  function operationFor(id) {
    var retained = (snapshot.operations || []).filter(function (op) {
      return op.taskId === id
    }).slice().reverse()
    var lost = uncertainOperations.filter(function (op) {
      return op.taskId === id
    }).slice().reverse()[0]
    var protectedOperation = retained.filter(function (op) {
      return op.submissionPending || op.submissionUnconfirmed
    })[0]
    var result = lost || protectedOperation || (operation && operation.taskId === id ? operation : retained[0])
    if (!result)
      return null
    return result === operation ? result : Object.assign({}, result, {
      reconnectRequired: true
    })
  }
  // Open details only for a current identity, after pointer settling.
  function openDetails(id, pointer) {
    if (!Logic.reconcileSelection(id, taskRows).key || pointer && Date.now() - layoutChangedAt < 300)
      return false
    selectedId = id
    if (pointer)
      keyboardCursor = false
    return true
  }
  // Tab switches and panel reopen also disarm the detail action cursor.
  function disarmCursor() {
    keyboardCursor = false
    detailView.disarmCursor()
  }
  // Escape from details preserves the list cursor without activating it.
  function back() {
    selectedId = ''
    keyboardCursor = false
  }
  // Keyboard navigation delegates to the same stable detail action model.
  function navigate(direction) {
    if (selectedRow) {
      detailView.navigate(direction)
      return
    }
    if (taskRows.length === 0) {
      if (keyboardCursor && direction === 0)
        action('setup', '')
      keyboardCursor = true
      return
    }
    var next = Logic.step(taskRows.map(function (r) {
      return r.key
    }), cursorId, keyboardCursor, direction)
    cursorId = next.key
    keyboardCursor = true
    if (next.activate)
      openDetails(cursorId, false)
    var index = taskRows.findIndex(function (r) {
      return r.key === cursorId
    })
    var item = rowRepeater.itemAt(index)
    if (item)
      listScroll.contentY = Math.max(0, Math.min(listScroll.contentHeight - listScroll.height, item.y))
  }
  implicitHeight: selectedRow ? detailView.implicitHeight : Math.min(maxHeight, listBody.implicitHeight)
  height: implicitHeight
  clip: true
  AgentTaskDetails {
    id: detailView
    width: parent.width
    visible: !!tasks.selectedRow
    maxHeight: tasks.maxHeight
    row: tasks.selectedRow
    operation: tasks.selectedOperation
    error: tasks.error
    pending: tasks.pending
    onAction: function (kind, id) {
      tasks.keyboardCursor = false
      if (kind === 'back')
        tasks.back()
      else if (kind !== 'inspect-result' && kind !== 'inspect-failure')
        tasks.action(kind, id)
    }
  }
  Flickable {
    id: listScroll
    anchors.fill: parent
    visible: !tasks.selectedRow
    contentWidth: width
    contentHeight: listBody.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    onContentYChanged: tasks.layoutChangedAt = Date.now()
    Column {
      id: listBody
      width: listScroll.width
      spacing: Style.space(12)
      Text {
        width: parent.width
        text: 'Agent tasks'
        color: Aranea.DesignTokens.foreground
        font.family: Aranea.Typography.uiFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        objectName: 'tasksError'
        width: parent.width
        visible: text !== ''
        text: tasks.error ? [Logic.text(tasks.error.message), Logic.text(tasks.error.recovery)].filter(Boolean).join('\n') : ''
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
        color: Aranea.DesignTokens.attention
        font.pixelSize: Style.font.body
      }
      Text {
        objectName: 'tasksEmpty'
        width: parent.width
        visible: tasks.taskRows.length === 0
        text: 'No tasks reported yet. Enable the provider adapter explicitly, or register a session and report activity. Usage remains available in the Usage tab.'
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
      }
      Repeater {
        id: rowRepeater
        model: tasks.taskRows
        Column {
          id: taskRow
          required property var modelData
          property string pressedKey: ''
          property string pressedLayout: ''
          objectName: 'taskRow'
          width: listBody.width
          spacing: Style.space(4)
          Text {
            objectName: 'taskSummary'
            width: parent.width
            text: taskRow.modelData.summary
            textFormat: Text.PlainText
            wrapMode: Text.WrapAnywhere
            color: Aranea.DesignTokens.foreground
            font.family: Aranea.Typography.uiFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            width: parent.width
            text: taskRow.modelData.providerLabel + ' · ' + taskRow.modelData.stateLabel + ' · ' + taskRow.modelData.freshnessLabel
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: taskRow.modelData.attention ? Aranea.DesignTokens.attention : Aranea.DesignTokens.foreground
            font.pixelSize: Style.font.body
          }
          Text {
            width: parent.width
            text: taskRow.modelData.context
            textFormat: Text.PlainText
            wrapMode: Text.WrapAnywhere
            color: Aranea.DesignTokens.foreground
            opacity: 0.65
            font.pixelSize: Style.font.body
          }
          Text {
            objectName: 'taskLastReport'
            width: parent.width
            text: taskRow.modelData.lastReportLabel
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Aranea.DesignTokens.foreground
            opacity: 0.65
            font.pixelSize: Style.font.body
          }
          Aranea.FilamentPill {
            objectName: 'taskDetailsControl'
            refined: true
            text: 'Details'
            hasCursor: tasks.keyboardCursor && tasks.cursorId === taskRow.modelData.key
            onPressed: {
              taskRow.pressedKey = taskRow.modelData.key
              taskRow.pressedLayout = tasks.layoutSignature
            }
            onPressCanceled: taskRow.pressedKey = ''
            onClicked: {
              if (taskRow.pressedKey && (taskRow.pressedKey !== taskRow.modelData.key || taskRow.pressedLayout !== tasks.layoutSignature))
                return
              tasks.openDetails(taskRow.modelData.key, !!taskRow.pressedKey)
              taskRow.pressedKey = ''
            }
          }
        }
      }
      Text {
        width: parent.width
        visible: tasks.taskRows.length === 0 || tasks.taskRows.some(function (r) {
          return !r.assigned
        })
        text: 'Unassigned tasks need an explicitly registered project and checkout. Open Project settings to add one; reporting activity never registers projects.'
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
      }
      Aranea.FilamentPill {
        objectName: 'taskSetup'
        refined: true
        text: 'Project settings'
        hasCursor: tasks.taskRows.length === 0 && tasks.keyboardCursor
        onClicked: tasks.action('setup', '')
      }
      TextEdit {
        objectName: 'taskSetupCommands'
        width: parent.width
        visible: tasks.taskRows.length === 0
        text: 'Activity is opt-in. Check provider availability, then copy an install command to enable reporting.\naranea agents adapter status claude\naranea agents adapter install claude\naranea agents adapter status codex\naranea agents adapter install codex\n\nConfigured hooks do not prove enabled/trusted hooks or observed activity. Review provider trust, then start a new native CLI session. Missing question hooks can use explicit reports.\naranea agents register --json-input\naranea agents report --json-input\n\nVerification stays not reported until explicitly reported. Session focus needs native process proof and reaches only the hosting terminal, not a tmux pane. Remove only the owned adapter hooks with:\naranea agents adapter remove claude\naranea agents adapter remove codex'
        readOnly: true
        selectByMouse: true
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.WrapAnywhere
        color: Aranea.DesignTokens.foreground
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: Style.font.body
      }
      Text {
        width: parent.width
        text: '↑↓ / j k tasks · enter details · tab Tasks / Usage'
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        opacity: 0.55
        font.pixelSize: Style.font.body
      }
    }
  }
}
