// Shared, inert Tasks/Usage navigation; remembers only deliberate user choices.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea
import "AgentTasksLogic.js" as Logic

Flow {
  id: tabs
  // Task rows determine the initial attention destination.
  property var taskRows: []
  // Usage discovery stays owned by the existing collector.
  property int usageCount: 0
  // Deliberate destination survives panel reopen.
  property string remembered: ''
  // Current destination before or after a deliberate choice.
  readonly property string destination: remembered === 'help' ? 'help' : Logic.destination(remembered, taskRows, usageCount)
  // Tab identity, never a row index.
  signal action(string kind, string taskId)
  // Select one fixed destination.
  function choose(kind) {
    if (kind !== 'tasks' && kind !== 'usage' && kind !== 'help')
      return
    remembered = kind
    action(kind, '')
  }
  // Keyboard Tab cycles the two destinations.
  function cycle() {
    choose(destination === 'tasks' ? 'usage' : destination === 'usage' ? 'help' : 'tasks')
  }
  spacing: Style.space(8)
  Aranea.FilamentPill {
    objectName: 'tasksTab'
    refined: true
    text: 'Tasks' + (tabs.taskRows.length ? ' · ' + tabs.taskRows.length : '')
    selected: tabs.destination === 'tasks'
    onClicked: tabs.choose('tasks')
  }
  Aranea.FilamentPill {
    objectName: 'usageTab'
    refined: true
    text: 'Usage'
    selected: tabs.destination === 'usage'
    onClicked: tabs.choose('usage')
  }
  Aranea.FilamentPill {
    objectName: 'helpTab'
    refined: true
    text: 'Help'
    selected: tabs.destination === 'help'
    onClicked: tabs.choose('help')
  }
}
