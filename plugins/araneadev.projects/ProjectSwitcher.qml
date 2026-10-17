// Compact project switcher: Enter returns to a project's open environment or starts its remembered profile.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea
import "ProjectSwitcher.js" as Switcher
import "ProjectProblems.js" as Problems

ColumnLayout {
  id: switcher
  objectName: 'projectSwitcher'
  // Registered projects.
  property var projects: []
  // Saved navigation metadata: pins and visits.
  property var navigation: ({})
  // Runtime snapshot with the environments that still have open windows.
  property var runtime: ({})
  // Installed tool probe used to pick a usable profile.
  property var tools: ({})
  // Cached branch observations for search and labels.
  property var gitCache: ({})
  // Shared project client whose start and return state the rows reflect.
  property var client: null
  // A start that first selects its checkout is still being prepared.
  property bool launching: false
  // Plain problem shown in place of the list when the registry cannot be read.
  property var loadProblem: null
  // Agent tasks, for the rows that have work to review.
  property var tasks: []
  // Review helper data by checkout id.
  property var reviews: ({})
  // Registry, discovery, action or activity work is running: nothing may begin.
  property bool systemBusy: false
  // Inert capture hosts refuse every action.
  property bool displayOnly: false
  // Shared pointer settlement gate.
  property var pointerGate: null
  // Search text.
  property string query: ''
  // Row the Enter key acts on, by project identity.
  property string highlightedId: ''
  // Return that found its windows gone, with the plain error to show.
  property var returnFailure: null
  // Rows in navigation order with their Enter action.
  readonly property var rows: Switcher.switcherRows(projects, navigation, query, runtime, tools, gitCache, tasks, reviews)
  // Enter target; falls back to the first row when the remembered one is filtered out.
  readonly property string cursorId: rows.some(function (row) {
    return row.id === switcher.highlightedId
  }) ? highlightedId : rows.length ? rows[0].id : ''
  // Position of the Enter target in the rows, or -1.
  readonly property int cursorIndex: rows.findIndex(function (row) {
    return row.id === switcher.cursorId
  })
  // A start or return is on its way or unconfirmed, so no other row may begin.
  readonly property bool clientBusy: launching || !!client && (client.submitting || client.preparing || client.acceptanceUnknown)
  // A request is on its way or an earlier start is unconfirmed: nothing new may begin.
  readonly property bool busy: displayOnly || systemBusy || clientBusy
  // Project whose own request is the one in flight, which keeps its own label.
  readonly property string busyOwnerId: client && client.environmentTarget ? client.environmentTarget.projectId || '' : ''
  // Project whose start is under way, including while the automatic checks run.
  readonly property string startingId: {
    var target = client ? client.environmentTarget : null
    if (!target || !client.autoChecking && !((client.submitting || client.acceptanceUnknown) && client.submissionMethod === 'startEnvironment'))
      return ''
    return target.projectId || ''
  }
  // Project whose return is under way.
  readonly property string returningId: {
    var target = client ? client.environmentTarget : null
    return target && client.submitting && client.submissionMethod === 'returnEnvironment' ? target.projectId || '' : ''
  }
  // The one problem to show, for the project that owns it.
  readonly property var problemInfo: {
    if (!client)
      return null
    if (returnFailure)
      return {
        id: returnFailure.projectId,
        problem: Problems.problem(returnFailure.error, {
          surface: 'switcher',
          actions: []
        }),
        offerStart: true
      }
    var target = client.environmentTarget
    if (!target || client.autoChecking || client.preparing && !client.acceptanceUnknown)
      return null
    if (!client.acceptanceUnknown && !client.requestError)
      return null
    var plain = Problems.problem(client.requestError || {
      code: 'ACCEPTANCE_UNKNOWN',
      message: client.error
    }, {
      surface: 'switcher',
      actions: client.acceptanceUnknown ? ['checkAgain'] : []
    })
    return {
      id: target.projectId,
      problem: plain,
      offerStart: client.submissionMethod === 'returnEnvironment' && !client.acceptanceUnknown
    }
  }
  // The cursor row owns the visible problem.
  readonly property bool problemShown: !!problemInfo && problemInfo.id === cursorId
  // Enter on a row: start, return, or fall back to the full layout.
  signal goRequested(var row)
  // Alt+Enter, Set up first and Add project: open Projects on this project, or setup when empty.
  signal expandRequested(string projectId)
  // The explicit Start offered after a failed return.
  signal startRequested(var row)
  // Escape.
  signal closeRequested
  // Forget the last visit's search, cursor and failure.
  function reset() {
    query = ''
    highlightedId = ''
    returnFailure = null
    search.text = ''
  }
  // Put the keyboard in the search field.
  function focusSearch() {
    if (displayOnly)
      forceActiveFocus()
    else
      search.forceActiveFocus()
  }
  // The row under the cursor, or null.
  function currentRow() {
    return cursorIndex >= 0 ? rows[cursorIndex] : null
  }
  // Move the Enter target by whole rows, staying inside the list.
  function move(delta) {
    if (!rows.length)
      return
    var next = Math.max(0, Math.min(rows.length - 1, cursorIndex + delta))
    highlightedId = rows[next].id
    list.positionViewAtIndex(next, ListView.Contain)
  }
  // Enter: run the row action, or fall back to the full layout.
  function go() {
    var row = currentRow()
    if (!row || displayOnly || loadProblem)
      return
    if (row.action.kind === 'setup')
      expand()
    else if (row.action.kind === 'review') {
      if (!systemBusy)
        goRequested(row)
    } else if (!busy)
      goRequested(row)
  }
  // Alt+Enter: open Projects on the row without launching.
  function expand() {
    var row = currentRow()
    if (!displayOnly && !systemBusy)
      expandRequested(row ? row.id : '')
  }
  // Label of a row's action, reflecting a start or return that is under way.
  function actionLabel(row) {
    if (row.id === startingId)
      return 'Starting…'
    if (row.id === returningId)
      return 'Returning…'
    if (row.action.kind === 'review')
      return systemBusy ? 'Busy right now' : row.action.label
    if (systemBusy || clientBusy && row.id !== busyOwnerId)
      return 'Busy right now'
    return row.action.label
  }
  // Escape and the navigation keys work from any focused control; true when handled.
  function handleKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0
    if (event.key === Qt.Key_Escape) {
      closeRequested()
    } else if (displayOnly) {
      return false
    } else if (event.key === Qt.Key_Down || ctrl && event.key === Qt.Key_J) {
      move(1)
    } else if (event.key === Qt.Key_Up || ctrl && event.key === Qt.Key_K) {
      move(-1)
    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
      if (alt)
        expand()
      else
        go()
    } else {
      return false
    }
    event.accepted = true
    return true
  }
  Keys.onPressed: function (event) {
    handleKey(event)
  }
  Connections {
    target: switcher.client
    function onOperationChanged(operation) {
      if (switcher.visible && operation && operation.error && operation.projectId && switcher.client.submissionMethod === 'returnEnvironment')
        switcher.returnFailure = {
          projectId: operation.projectId,
          error: operation.error
        }
    }
    function onEnvironmentRequestStarted() {
      switcher.returnFailure = null
    }
  }
  spacing: Style.space(8)
  TextField {
    id: search
    objectName: 'projectSwitcherSearch'
    Layout.fillWidth: true
    placeholderText: 'Search projects…'
    palette.placeholderText: Util.alpha(Color.foreground, 0.55)
    enabled: !switcher.displayOnly
    onTextEdited: {
      switcher.query = text
      switcher.highlightedId = ''
    }
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: Style.font.body
    color: Color.foreground
    background: Rectangle {
      color: Util.alpha(Color.foreground, 0.06)
      radius: Style.space(3)
    }
    Keys.onPressed: function (event) {
      switcher.handleKey(event)
    }
  }
  ProjectProblem {
    objectName: 'projectSwitcherLoadProblem'
    Layout.fillWidth: true
    problem: switcher.loadProblem
    displayOnly: switcher.displayOnly
    pointerGate: switcher.pointerGate
  }
  ListView {
    id: list
    objectName: 'projectSwitcherList'
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: Style.space(44)
    visible: switcher.rows.length > 0 && !switcher.loadProblem
    clip: true
    model: switcher.rows
    boundsBehavior: Flickable.StopAtBounds
    spacing: Style.space(2)
    delegate: Aranea.ActionButton {
      id: row
      required property var modelData
      width: ListView.view.width
      implicitHeight: Style.space(40)
      objectName: 'projectSwitcherRow:' + modelData.id
      variant: 'navigation'
      hasCursor: modelData.id === switcher.cursorId
      activeFocusOnTab: false
      enabled: !switcher.displayOnly
      pointerGate: switcher.pointerGate
      Accessible.name: modelData.name + ', ' + switcher.actionLabel(modelData)
      onClicked: {
        switcher.highlightedId = modelData.id
        switcher.go()
      }
      Aranea.UiLabel {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(12)
        anchors.right: chip.visible ? chip.left : action.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: row.modelData.name + (row.modelData.branch ? ' · ' + row.modelData.branch : '')
        font.pixelSize: Style.font.body
        font.bold: row.hasCursor
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
      }
      Aranea.UiLabel {
        id: chip
        objectName: 'projectSwitcherReviewChip:' + row.modelData.id
        anchors.right: action.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        visible: row.modelData.review && row.modelData.action.kind !== 'review'
        text: 'Review'
        font.bold: true
        color: Aranea.DesignTokens.accent
        wrapMode: Text.NoWrap
      }
      Aranea.UiLabel {
        id: action
        objectName: 'projectSwitcherAction:' + row.modelData.id
        anchors.right: parent.right
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        text: switcher.actionLabel(row.modelData)
        opacity: 0.7
        wrapMode: Text.NoWrap
      }
    }
  }
  ColumnLayout {
    objectName: 'projectSwitcherEmpty'
    Layout.fillWidth: true
    Layout.fillHeight: true
    visible: switcher.rows.length === 0 && !switcher.loadProblem
    spacing: Style.space(8)
    Aranea.UiLabel {
      Layout.fillWidth: true
      text: switcher.query ? 'No matching results.' : 'No projects yet'
      opacity: 0.7
    }
    Aranea.ActionButton {
      objectName: 'projectSwitcherAddProject'
      visible: !switcher.query
      text: 'Add project'
      variant: 'primary'
      enabled: !switcher.displayOnly && !switcher.systemBusy
      pointerGate: switcher.pointerGate
      onClicked: switcher.expandRequested('')
    }
    Item {
      Layout.fillHeight: true
    }
  }
  ProjectProblem {
    id: problemView
    objectName: 'projectSwitcherProblem'
    Layout.fillWidth: true
    problem: switcher.problemShown ? switcher.problemInfo.problem : null
    displayOnly: switcher.displayOnly
    actionsEnabled: !!switcher.client && !switcher.client.submitting
    pointerGate: switcher.pointerGate
    onActionRequested: function (id) {
      if (id === 'checkAgain' && !switcher.displayOnly && !switcher.client.submitting)
        switcher.client.checkEnvironmentActivation()
    }
  }
  Aranea.ActionButton {
    objectName: 'projectSwitcherStart'
    visible: switcher.problemShown && switcher.problemInfo.offerStart && !!switcher.currentRow() && !!switcher.currentRow().startTarget
    text: 'Start'
    variant: 'primary'
    enabled: !switcher.busy
    pointerGate: switcher.pointerGate
    onClicked: {
      if (!switcher.busy)
        switcher.startRequested(switcher.currentRow())
    }
  }
  Aranea.UiLabel {
    objectName: 'projectSwitcherHint'
    Layout.fillWidth: true
    text: 'Enter: go · Alt+Enter: open in Projects · Esc: close'
    opacity: 0.6
    wrapMode: Text.NoWrap
    elide: Text.ElideRight
  }
}
