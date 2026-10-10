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
  // Help is a read-only destination alongside Tasks and Usage.
  property bool helpActive: false
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
  // Advanced setup text is a local disclosure, never an owner action.
  property bool setupGuideExpanded: false
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
    if (helpActive) {
      helpScroll.contentY = Math.max(0, Math.min(helpScroll.contentHeight - helpScroll.height, helpScroll.contentY + direction * Style.space(48)))
      return
    }
    if (selectedRow) {
      detailView.navigate(direction)
      return
    }
    if (taskRows.length === 0) {
      var emptyNext = Logic.step(['setup', 'guide'], cursorId, keyboardCursor, direction)
      cursorId = emptyNext.key
      keyboardCursor = true
      if (emptyNext.activate) {
        if (cursorId === 'guide')
          setupGuideExpanded = !setupGuideExpanded
        else
          action('setup', '')
      }
      var target = cursorId === 'guide' ? setupGuide : setupButton
      listScroll.contentY = Math.max(0, Math.min(listScroll.contentHeight - listScroll.height, target.y))
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
  implicitHeight: helpActive ? Math.min(maxHeight, helpBody.implicitHeight) : selectedRow ? detailView.implicitHeight : Math.min(maxHeight, listBody.implicitHeight)
  height: implicitHeight
  clip: true
  Flickable {
    id: helpScroll
    anchors.fill: parent
    visible: tasks.helpActive
    contentWidth: width
    contentHeight: helpBody.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    Aranea.WorkflowHelp {
      id: helpBody
      objectName: 'agentWorkflowHelp'
      width: helpScroll.width
      topic: 'agents'
    }
  }
  AgentTaskDetails {
    id: detailView
    width: parent.width
    visible: !tasks.helpActive && !!tasks.selectedRow
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
    visible: !tasks.helpActive && !tasks.selectedRow
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
        text: tasks.taskRows.length ? tasks.taskRows.length + ' tasks · ' + tasks.taskRows.filter(function (r) {
          return r.attention
        }).length + ' need attention' : 'Agent tasks'
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
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.attention
        font.pixelSize: Style.font.body
      }
      Text {
        objectName: 'tasksEmpty'
        width: parent.width
        visible: tasks.taskRows.length === 0
        text: 'No tasks yet. Enable reporting below, then start a new agent session.'
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
      }
      Repeater {
        id: rowRepeater
        model: tasks.taskRows
        Rectangle {
          id: taskRow
          required property var modelData
          property string pressedKey: ''
          property string pressedLayout: ''
          objectName: 'taskRow'
          width: listBody.width
          height: cardBody.implicitHeight + Style.space(24)
          radius: Aranea.DesignTokens.cornerRadius
          color: tasks.keyboardCursor && tasks.cursorId === modelData.key ? Aranea.DesignTokens.selectedFill : Qt.alpha(Aranea.DesignTokens.foreground, 0.035)
          border.width: 1
          border.color: Qt.alpha(modelData.attention ? Aranea.DesignTokens.attention : Aranea.DesignTokens.foreground, 0.22)
          Column {
            id: cardBody
            x: Style.space(12)
            y: Style.space(12)
            width: parent.width - Style.space(24)
            spacing: Style.space(6)
            Flow {
              width: parent.width
              spacing: Style.space(8)
              Rectangle {
                width: stateLabel.implicitWidth + Style.space(12)
                height: stateLabel.implicitHeight + Style.space(6)
                radius: height / 2
                color: Qt.alpha(taskRow.modelData.attention ? Aranea.DesignTokens.attention : Aranea.DesignTokens.accent, 0.12)
                Text {
                  id: stateLabel
                  anchors.centerIn: parent
                  text: taskRow.modelData.stateLabel
                  textFormat: Text.PlainText
                  color: taskRow.modelData.attention ? Aranea.DesignTokens.attention : Aranea.DesignTokens.accent
                  font.family: Aranea.Typography.uiFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
              Text {
                width: Math.min(implicitWidth, parent.width)
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: taskRow.modelData.providerLabel
                color: Aranea.DesignTokens.foreground
                opacity: 0.65
                font.family: Aranea.Typography.uiFamily
                font.pixelSize: Style.font.caption
              }
            }
            Text {
              objectName: 'taskSummary'
              width: parent.width
              text: taskRow.modelData.summary
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
              color: Aranea.DesignTokens.foreground
              font.family: Aranea.Typography.uiFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              width: parent.width
              text: taskRow.modelData.assigned ? [taskRow.modelData.projectLabel, taskRow.modelData.branch].filter(Boolean).join(' · ') : taskRow.modelData.associationLabel
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Aranea.DesignTokens.foreground
              opacity: 0.65
              font.family: Aranea.Typography.uiFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              objectName: 'taskLastReport'
              width: parent.width
              text: taskRow.modelData.lastReportLabel + (taskRow.modelData.freshnessLabel !== 'Connected' ? ' · ' + taskRow.modelData.freshnessLabel : '')
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              color: Aranea.DesignTokens.foreground
              opacity: 0.65
              font.family: Aranea.Typography.uiFamily
              font.pixelSize: Style.font.caption
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
      }
      Text {
        width: parent.width
        visible: tasks.taskRows.length === 0 || tasks.taskRows.some(function (r) {
          return !r.assigned
        })
        text: 'Register a project and checkout to enable session actions.'
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        font.pixelSize: Style.font.body
      }
      Aranea.FilamentPill {
        id: setupButton
        objectName: 'taskSetup'
        visible: tasks.taskRows.length === 0 || tasks.taskRows.some(function (r) {
          return !r.assigned
        })
        refined: true
        text: 'Project settings'
        hasCursor: tasks.taskRows.length === 0 && tasks.keyboardCursor && tasks.cursorId === 'setup'
        onClicked: tasks.action('setup', '')
      }
      TextEdit {
        width: parent.width
        visible: tasks.taskRows.length === 0
        text: 'Enable reporting (opt-in)\naranea agents adapter install claude\naranea agents adapter install codex\n\nReview provider trust, then start a new CLI session.'
        readOnly: true
        selectByMouse: true
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.Wrap
        color: Aranea.DesignTokens.foreground
        font.family: Aranea.Typography.uiFamily
        font.pixelSize: Style.font.body
      }
      Aranea.FilamentPill {
        id: setupGuide
        objectName: 'taskSetupGuide'
        visible: tasks.taskRows.length === 0
        refined: true
        text: tasks.setupGuideExpanded ? 'Hide setup details' : 'Setup details'
        hasCursor: tasks.keyboardCursor && tasks.cursorId === 'guide'
        cursorOutlineMargin: 0
        onClicked: tasks.setupGuideExpanded = !tasks.setupGuideExpanded
      }
      TextEdit {
        objectName: 'taskSetupCommands'
        width: parent.width
        visible: tasks.taskRows.length === 0 && tasks.setupGuideExpanded
        text: 'Enable reporting (opt-in)\naranea agents adapter install claude\naranea agents adapter install codex\n\nReview provider trust, then start a new CLI session. Configured hooks do not prove trust or observed activity.\n\nCheck availability\naranea agents adapter status claude\naranea agents adapter status codex\n\nRemove owned hooks\naranea agents adapter remove claude\naranea agents adapter remove codex'
        readOnly: true
        selectByMouse: true
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.Wrap
        color: Aranea.DesignTokens.foreground
        font.family: Aranea.Typography.uiFamily
        font.pixelSize: Style.font.body
      }
      Text {
        width: parent.width
        text: '↑↓ / j k tasks · enter details · tab Tasks / Usage / Help'
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Aranea.DesignTokens.foreground
        opacity: 0.55
        font.pixelSize: Style.font.body
      }
    }
  }
}
