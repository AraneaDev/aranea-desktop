// Actual Tasks prose preserves word boundaries and bounds oversized tokens.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.agents" as Agents
import "plugins/araneadev.agents/AgentTasksLogic.js" as Logic

ShellRoot {
  QmlTest {
    id: t
  }
  TextMetrics {
    id: measure
    text: 'terminal'
    font.pixelSize: 26
  }
  FloatingWindow {
    visible: true
    width: 420
    height: 680
    Agents.AgentTasks {
      id: tasks
      width: 380
      maxHeight: 300
      captureActive: true
      snapshot: ({
          tasks: [
            {
              taskId: 'prose',
              provider: 'claude',
              description: 'terminal terminal terminal',
              reportedState: 'needs-input'
            }
          ]
        })
    }
    Agents.AgentTaskDetails {
      id: details
      width: 380
      maxHeight: 300
      row: Logic.rows({
        tasks: [
          {
            taskId: 'prose',
            provider: 'claude',
            description: 'terminal terminal terminal',
            reportedState: 'needs-input',
            question: 'terminal terminal terminal'
          }
        ]
      })[0]
    }
  }
  Component.onCompleted: t.step(60, function () {
    var labels = [t.findChild(tasks, 'taskSummary'), t.findChild(details, 'detailsSummary'), t.findChild(details, 'reportedQuestion')]
    labels.forEach(function (label) {
      label.font.pixelSize = 26
      measure.font = label.font
      label.width = measure.advanceWidth * 1.9
    })
    t.step(50, function () {
      labels.forEach(function (label) {
        t.equal(label.lineCount, 3, 'narrow large-font prose keeps each terminal word intact: ' + label.objectName)
        label.text = new Array(80).fill('x').join('')
      })
      t.step(50, function () {
        labels.forEach(function (label) {
          t.check(label.lineCount > 1 && label.paintedWidth <= label.width + 1, 'oversized tokens remain bounded: ' + label.objectName)
        })
        t.done()
      })
    })
  })
}
